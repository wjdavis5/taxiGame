#!/usr/bin/env ruby
# Minimal App Store Connect client for release checks.
#
#   ruby asc.rb status    # app record, latest builds, version state, submission
#   ruby asc.rb builds    # every build and its processing state
#   ruby asc.rb version   # the editable version and what is attached to it
#
# Auth comes from .env at the repo root (ASC_KEY_ID, ASC_ISSUER_ID) plus the
# AuthKey_<KEY_ID>.p8 private key. Both are gitignored. The key file is looked
# up by that exact name in ~/Downloads and ~/.appstoreconnect/private_keys,
# never by globbing AuthKey_*.p8 and taking the first hit (issue #115: the
# first glob hit signed the JWT while its header still named ASC_KEY_ID, and
# Apple answered 401 to every call).
#
# Uses only Ruby's stdlib - no gems, no bundler.

require 'openssl'; require 'base64'; require 'json'; require 'net/http'; require 'uri'

APP_ID = '6804508589'

def repo_root
  @repo_root ||= `git rev-parse --show-toplevel`.strip
end

def env
  @env ||= begin
    path = File.join(repo_root, '.env')
    abort("missing #{path} - needs ASC_KEY_ID and ASC_ISSUER_ID") unless File.exist?(path)
    File.read(path).lines.map { |l|
      k, _, v = l.strip.partition('='); [k, v.gsub(/\A["']|["']\z/, '')]
    }.to_h
  end
end

# Apple answers 401 whenever the JWT's kid header and the signing key
# disagree, so the file used here must be the one ASC_KEY_ID names — not
# whichever AuthKey_*.p8 a glob hits first (issue #115: a second key sitting
# in ~/Downloads signed every request on a machine whose ASC_KEY_ID pointed
# at the other one). Both folders below are the ones xcodebuild and fastlane
# search by convention, and CI writes exactly this filename
# (.github/workflows/ios-release.yml), so the name is not optional.
def private_key_path
  name = "AuthKey_#{env.fetch('ASC_KEY_ID')}.p8"
  dirs = [File.expand_path('~/Downloads'),
          File.expand_path('~/.appstoreconnect/private_keys')]
  dirs.map { |dir| File.join(dir, name) }.find { |path| File.exist?(path) } or
    abort("missing #{name} in #{dirs.join(' or ')} - the .p8 must be named " +
          'exactly AuthKey_<ASC_KEY_ID>.p8 for the ASC_KEY_ID in .env')
end

def jwt
  @jwt ||= begin
    b64 = ->(s) { Base64.urlsafe_encode64(s).delete('=') }
    header  = b64.call({ alg: 'ES256', kid: env.fetch('ASC_KEY_ID'), typ: 'JWT' }.to_json)
    now     = Time.now.to_i
    payload = b64.call({ iss: env.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 900,
                         aud: 'appstoreconnect-v1' }.to_json)
    ec  = OpenSSL::PKey::EC.new(File.read(private_key_path))
    der = ec.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest("#{header}.#{payload}"))
    r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
    "#{header}.#{payload}.#{b64.call(r + s)}"
  end
end

def get(path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{jwt}")
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
  [res.code.to_i, (res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue {}))]
end

def builds(limit = 5)
  code, b = get("/v1/builds?filter[app]=#{APP_ID}&limit=#{limit}&sort=-uploadedDate")
  abort("builds query failed: HTTP #{code}") unless code == 200
  b['data'] || []
end

def editable_version
  code, v = get("/v1/apps/#{APP_ID}/appStoreVersions?limit=10")
  abort("versions query failed: HTTP #{code}") unless code == 200
  data = v['data'] || []
  data.find { |x| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED
                     METADATA_REJECTED INVALID_BINARY].include?(x.dig('attributes', 'appStoreState')) } || data.first
end

def print_builds
  puts 'BUILDS'
  list = builds
  puts '  (none uploaded)' if list.empty?
  list.each do |x|
    a = x['attributes']
    puts format('  build %-6s %-12s uploaded %s', a['version'], a['processingState'], a['uploadedDate'])
  end
end

def print_version
  v = editable_version
  return puts('VERSION: none') unless v
  a = v['attributes']
  # Issue #111: AFTER_APPROVAL and SCHEDULED both put the build on the
  # store without a human — approval (or the clock) is the release. MANUAL
  # is what the submit lane writes. The raw releaseType reads as a harmless
  # enum value, so say what it actually means next to it.
  auto = ['AFTER_APPROVAL', 'SCHEDULED'].include?(a['releaseType'])
  puts 'VERSION'
  puts "  #{a['versionString']}  state=#{a['appStoreState']}  " \
       "release=#{a['releaseType']}#{auto ? ' (goes live automatically)' : ''}"

  code, full = get("/v1/appStoreVersions/#{v['id']}?include=build")
  attached = full.dig('data', 'relationships', 'build', 'data')
  if attached
    _, bd = get("/v1/builds/#{attached['id']}")
    ba = bd.dig('data', 'attributes') || {}
    puts "  attached build: #{ba['version']} (#{ba['processingState']})"
  else
    puts '  attached build: NONE'
  end

  code, _ = get("/v1/appStoreVersions/#{v['id']}/appStoreVersionSubmission")
  puts "  submitted for review: #{code == 200 ? 'YES' : 'no'}"
end

def print_blockers
  v = editable_version
  return unless v
  id = v['id']
  puts 'LISTING'
  code, l = get("/v1/appStoreVersions/#{id}/appStoreVersionLocalizations?limit=5")
  (l['data'] || []).each do |loc|
    a = loc['attributes']
    %w[description keywords supportUrl].each do |k|
      puts format('  %-14s %s', k, a[k].to_s.empty? ? '*** EMPTY ***' : 'set')
    end
    c2, sets = get("/v1/appStoreVersionLocalizations/#{loc['id']}/appScreenshotSets?limit=5")
    (sets['data'] || []).each do |s|
      c3, shots = get("/v1/appScreenshotSets/#{s['id']}/appScreenshots?limit=20")
      n = (shots['data'] || []).size
      puts format('  %-14s %s: %d', 'screenshots', s.dig('attributes', 'screenshotDisplayType'), n)
    end
  end
end

case ARGV[0]
when 'builds'  then print_builds
when 'version' then print_version
when nil, 'status'
  print_builds; puts; print_version; puts; print_blockers
  puts
  puts 'NOTE: App Privacy is not exposed on this API - verify it in the App Store Connect UI.'
else
  abort("unknown command #{ARGV[0].inspect} (want: status, builds, version)")
end
