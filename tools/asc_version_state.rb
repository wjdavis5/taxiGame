#!/usr/bin/env ruby
# Reports where a version string stands in App Store Connect, for the iOS
# release workflow's submit decision (issues #89 and #93).
#
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY=... \
#     ruby asc_version_state.rb 1.0.1
#
# Stdout is exactly one verdict:
#   REVIEW_IN_FLIGHT  some reviewSubmission for the app has not COMPLETEd.
#                     A live submission holds Apple's review slot for the
#                     app, so no second one may be created — whatever the
#                     version records said. Issue #93: the first run of the
#                     #89 gate read a version list that came back without
#                     the in-review 1.0.0 as NONE, "submitted", and crashed
#                     into Apple's "a relationship value is not acceptable
#                     for the current resource state" (build 1074).
#   NONE              no appStoreVersions record carries the string AND the
#                     second source agrees no submission is active — the
#                     never-yet-submitted case.
#   otherwise         one line per matching record's appStoreState
#                     (PREPARE_FOR_SUBMISSION, READY_FOR_SALE, ...).
# Everything diagnostic goes to stderr, so stdout stays machine-parseable.
#
# Fail closed, always (the #93 lesson): an answer the gate cannot trust is
# an error, never a verdict. A non-200, an unparseable body, a missing data
# array, an empty appStoreVersions list (this app is on the store, so that
# answer means the query landed wrong — wrong app, a key whose role cannot
# see versions, an API change — not "nothing was ever submitted"), or a
# page-limit-sized answer the client-side matching could not have received
# in full: each prints the reason to stderr and exits 1, and the workflow's
# `set -e` fails the run. Defaulting to "TestFlight only" on a query
# failure is exactly the silent drop this gate exists to prevent (#89);
# defaulting to "submit" is worse (#93), so neither default exists.
#
# The second source is GET /v1/reviewSubmissions?filter[app]=... Apple's
# OpenAPI spec also offers an app-scoped /v1/apps/{id}/reviewSubmissions
# carrying the same records; the filter form is used so both queries read
# as "resource path + query" the same way. That spec gives the state enum as
# READY_FOR_REVIEW, WAITING_FOR_REVIEW, IN_REVIEW, UNRESOLVED_ISSUES,
# CANCELING, COMPLETING, COMPLETE; fastlane's mirror of the spec
# (spaceship's ReviewSubmission model) still lacks COMPLETING, which is
# exactly why the classification below is "COMPLETE, or active" — never an
# enumeration of active values. A nil state, or one Apple invents after
# this was written, lands on the active side of that line.
#
# Credentials come from the environment, never a key file: the workflow runs
# this step before the one that installs the .p8 for xcodebuild and fastlane,
# so the file that step writes does not exist yet.
#
# Test seam: ASC_FIXTURE_APP_STORE_VERSIONS and ASC_FIXTURE_REVIEW_SUBMISSIONS,
# when set, each hold a full JSON response body for their named query and
# replace its HTTP call entirely. release_submit_gate_test.dart drives the
# real decision logic through them — no network, no credentials — which is
# the only way the Dart suite can execute Ruby behavior at all. With both
# set, no secret is required and no socket is opened.
#
# Uses only Ruby's stdlib — no gems, no bundler. The JWT construction is a
# port of .claude/skills/release/scripts/asc.rb, which this repository has
# used against the live API since the first submission.

require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'

APP_ID = '6804508589'   # Cab Hustle; see CLAUDE.md "Identity".
PAGE_LIMIT = 200        # the ceiling Apple's OpenAPI spec puts on both list
                        # endpoints' limit parameter, and therefore the size
                        # at which "everything fit on one page" stops being
                        # a safe assumption for client-side matching.

def fail!(message)
  warn message
  exit 1
end

# Query name => env var holding its injected fixture body. A fixture that is
# unset or blank means that query runs against the live API.
FIXTURES = {
  appStoreVersions: 'ASC_FIXTURE_APP_STORE_VERSIONS',
  reviewSubmissions: 'ASC_FIXTURE_REVIEW_SUBMISSIONS'
}.freeze

version = ARGV[0].to_s.strip
fail!('usage: ruby asc_version_state.rb <marketing-version>   e.g. 1.0.1') if version.empty?

# Credentials are demanded only for queries that will really run, so the
# fixture seam works on a machine with no secrets at all — otherwise the
# Dart behavioral tests would need real ASC keys to exercise logic that
# never touches the network.
if FIXTURES.values.any? { |name| ENV[name].to_s.strip.empty? }
  %w[ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY].each do |name|
    if ENV[name].to_s.strip.empty?
      fail!("#{name} is not set - the workflow must pass it in this step's env")
    end
  end
end

# Short-lived ES256 JWT signed with the raw .p8 contents from the env. ASC's
# API accepts no other auth, and no gems are needed: OpenSSL signs and ASN.1
# splits the DER signature into the raw r||s concatenation ES256 wants.
def jwt
  @jwt ||= begin
    b64 = ->(s) { Base64.urlsafe_encode64(s).delete('=') }
    header  = b64.call({ alg: 'ES256', kid: ENV.fetch('ASC_KEY_ID'), typ: 'JWT' }.to_json)
    now     = Time.now.to_i
    payload = b64.call({ iss: ENV.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 900,
                         aud: 'appstoreconnect-v1' }.to_json)
    ec  = OpenSSL::PKey::EC.new(ENV.fetch('ASC_PRIVATE_KEY'))
    der = ec.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest("#{header}.#{payload}"))
    r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
    "#{header}.#{payload}.#{b64.call(r + s)}"
  rescue OpenSSL::PKey::ECError, ArgumentError => e
    # A secret pasted wrong is a config failure, not a crash: name it the
    # way the HTTP failures below are named, with the same exit 1.
    fail!("ASC_PRIVATE_KEY is not a usable EC private key: #{e.message}")
  end
end

# GET one ASC list endpoint, or parse its injected fixture instead. `what`
# names the query in every failure message, so a red CI log says which half
# of the two-source decision died.
def asc_get(path, fixture_var, what)
  fixture = ENV[fixture_var]
  unless fixture.nil? || fixture.strip.empty?
    begin
      return JSON.parse(fixture)
    rescue JSON::ParserError => e
      fail!("#{fixture_var} is not valid JSON: #{e.message}")
    end
  end

  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  request = Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{jwt}")
  # Rescue at the call site, not Net::HTTP internals: a runner without egress
  # or a slow API raises (SocketError, Net::OpenTimeout, ...), and a backtrace
  # ending in exit 1 is worth less in a CI log than one line naming the cause.
  response = begin
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
      http.request(request)
    end
  rescue StandardError => e
    fail!("#{what} query raised #{e.class}: #{e.message}")
  end

  unless response.code.to_i == 200
    fail!("#{what} query failed: HTTP #{response.code} #{response.body.to_s[0, 400]}")
  end

  begin
    JSON.parse(response.body)
  rescue JSON::ParserError
    fail!("#{what} returned unparseable JSON: #{response.body.to_s[0, 400]}")
  end
end

# Source 1: the app's version records. Match the string client-side rather
# than trusting a server-side filter[versionString] to exist and behave as
# documented; an app never carries enough versions for the unfiltered list
# to paginate, and the guard below turns "would paginate" into a loud
# failure instead of a silently truncated answer.
versions = asc_get("/v1/apps/#{APP_ID}/appStoreVersions?limit=#{PAGE_LIMIT}",
                   FIXTURES[:appStoreVersions], 'appStoreVersions')['data']
fail!('appStoreVersions returned no data array - not a shape Apple sends; ' \
      'refusing to read it as an inventory') if versions.nil?

if versions.empty?
  # #93's failure mode in its purest form. The app is live on the store, so
  # it always has at least one version record; an empty list means the
  # answer itself is broken (wrong app id, a key whose role cannot see
  # versions, an API change), and the run that trusted it as "no version
  # yet" submitted over a live review. An error here fails that run loudly
  # instead of repeating the mistake.
  fail!("appStoreVersions returned an empty list for app #{APP_ID} - the app has live " \
        'versions, so this answer is wrong, not "no version yet"; refusing to say NONE')
end

if versions.length >= PAGE_LIMIT
  fail!("appStoreVersions returned #{versions.length} records, the page limit - " \
        'client-side matching assumes they all fit on one page')
end

# Source 2: the app's review submissions, deliberately not scoped to the
# requested version — issue #93 asks for "never submit while a review
# submission is active, whatever appStoreVersions says". A submission that
# has not COMPLETEd still occupies Apple's review slot; creating another is
# what Apple refused in the build-1074 run.
submissions = asc_get("/v1/reviewSubmissions?filter[app]=#{APP_ID}&limit=#{PAGE_LIMIT}",
                      FIXTURES[:reviewSubmissions], 'reviewSubmissions')['data'] || []
if submissions.length >= PAGE_LIMIT
  fail!("reviewSubmissions returned #{submissions.length} records, the page limit - " \
        'client-side scanning assumes they all fit on one page')
end

# "COMPLETE, or active": every state except COMPLETE — including COMPLETING,
# which fastlane's mirror of the spec predates, and nil, which means Apple
# changed the shape — leaves a submission that may hold the review slot.
active = submissions.select { |s| s.dig('attributes', 'state') != 'COMPLETE' }

matching = versions.select { |r| r.dig('attributes', 'versionString') == version }

if matching.empty?
  # The inventory goes to stderr even when the second source overrides the
  # verdict below: #93's postmortem could not tell an empty list from a
  # wrong-key answer precisely because the NONE path used to print nothing.
  inventory = versions.map do |r|
    "#{r.dig('attributes', 'versionString') || '?'}=#{r.dig('attributes', 'appStoreState') || 'UNKNOWN'}"
  end.join(', ')
  warn "appStoreVersions for app #{APP_ID}: #{versions.length} record(s), none for #{version} " \
       "(#{inventory})"
end

if active.any?
  states = active.map { |s| s.dig('attributes', 'state') || 'UNKNOWN' }.uniq.join(', ')
  warn "app #{APP_ID} has #{active.length} unfinished reviewSubmission(s): #{states}"
  puts 'REVIEW_IN_FLIGHT'
elsif matching.empty?
  # Only reachable when the second source agrees nothing is in flight.
  puts 'NONE'
else
  warn "app #{APP_ID} has #{matching.length} appStoreVersions record(s) for #{version}"
  matching.each do |record|
    # A nil state would be one Apple added after this was written; printing
    # UNKNOWN keeps it out of the workflow's editable list, so a state this
    # pipeline has never seen can never trigger a submission.
    puts(record.dig('attributes', 'appStoreState') || 'UNKNOWN')
  end
end
