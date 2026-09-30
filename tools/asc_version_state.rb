#!/usr/bin/env ruby
# Reports where a version string stands in App Store Connect, for the iOS
# release workflow's submit decision (issue #89).
#
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_PRIVATE_KEY=... \
#     ruby asc_version_state.rb 1.0.1
#
# Stdout is one line per appStoreVersions record whose versionString matches
# the argument — its appStoreState (PREPARE_FOR_SUBMISSION, READY_FOR_SALE,
# ...) — or the single word NONE when no record carries that string yet.
# Everything diagnostic goes to stderr, so stdout stays machine-parseable.
#
# The workflow submits for review only when every line names a state Apple
# still considers editable, which makes the decision from Apple's own record
# of what has been submitted. The old gate diffed pubspec.yaml against
# HEAD~1, so a bump whose own run died before the Submit step looked
# "unchanged" to every later push and shipped TestFlight only forever.
#
# Any failure — missing credentials, non-200, unparseable body — prints the
# reason to stderr and exits 1, and the workflow's `set -e` fails the run.
# Defaulting to "TestFlight only" on a query failure is exactly the silent
# drop this gate exists to prevent.
#
# Credentials come from the environment, never a key file: the workflow runs
# this step before the one that installs the .p8 for xcodebuild and fastlane,
# so the file that step writes does not exist yet.
#
# Uses only Ruby's stdlib — no gems, no bundler. The JWT construction is a
# port of .claude/skills/release/scripts/asc.rb, which this repository has
# used against the live API since the first submission.

require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'

APP_ID = '6804508589'   # Cab Hustle; see CLAUDE.md "Identity".

def fail!(message)
  warn message
  exit 1
end

%w[ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY].each do |name|
  if ENV[name].to_s.strip.empty?
    fail!("#{name} is not set - the workflow must pass it in this step's env")
  end
end

version = ARGV[0].to_s.strip
fail!('usage: ruby asc_version_state.rb <marketing-version>   e.g. 1.0.1') if version.empty?

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

# Fetch the app's version records and match the string client-side rather
# than trusting a server-side filter[versionString] to exist and behave as
# documented; an app never carries enough versions for the unfiltered list
# to paginate, and the guard below turns "would paginate" into a loud
# failure instead of a silently truncated answer.
uri = URI("https://api.appstoreconnect.apple.com/v1/apps/#{APP_ID}/appStoreVersions?limit=200")
request = Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{jwt}")
# Rescue at the call site, not Net::HTTP internals: a runner without egress
# or a slow API raises (SocketError, Net::OpenTimeout, ...), and a backtrace
# ending in exit 1 is worth less in a CI log than one line naming the cause.
response = begin
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
    http.request(request)
  end
rescue StandardError => e
  fail!("appStoreVersions query raised #{e.class}: #{e.message}")
end

unless response.code.to_i == 200
  fail!("appStoreVersions query failed: HTTP #{response.code} #{response.body.to_s[0, 400]}")
end

body = begin
  JSON.parse(response.body)
rescue JSON::ParserError
  fail!("appStoreVersions returned unparseable JSON: #{response.body.to_s[0, 400]}")
end

records = body['data'] || []
if records.length >= 200
  fail!("appStoreVersions returned #{records.length} records, the page limit - " \
        'client-side matching assumes they all fit on one page')
end

matching = records.select { |r| r.dig('attributes', 'versionString') == version }

if matching.empty?
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
