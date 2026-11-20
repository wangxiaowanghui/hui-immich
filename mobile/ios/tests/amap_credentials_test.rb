require 'minitest/autorun'
require 'tmpdir'
require_relative '../scripts/amap_credentials'
class AmapCredentialsTest < Minitest::Test
  def with_source(text)
    Dir.mktmpdir do |folder|
      file = File.join(folder, 'user_info.properties')
      File.write(file, text)
      yield file, folder
    end
  end
  def test_ios_only_and_no_web_fallback
    with_source("AMAP_WEB_PASSCODE=#{'a' * 32}\n") { |file, _| assert_equal '', AmapCredentials.read(file) }
    with_source("AMAP_IOS_PASSCODE=#{'b' * 32}\n") { |file, _| assert_equal 'b' * 32, AmapCredentials.read(file) }
  end
  def test_rejects_duplicate_and_injection_without_secret_in_error
    ['AMAP_IOS_PASSCODE=x$(run)', "AMAP_IOS_PASSCODE=#{'b' * 32}\nAMAP_IOS_PASSCODE=#{'b' * 32}"].each do |source|
      with_source(source) do |file, _|
        error = assert_raises(RuntimeError) { AmapCredentials.read(file) }
        refute_includes error.message, '$(run)'
        refute_includes error.message, 'b' * 32
      end
    end
  end
  def test_generated_permissions_and_stale_key_cleared
    with_source("AMAP_IOS_PASSCODE=#{'c' * 32}\n") do |file, folder|
      previous = ENV['IMMICH_CREDENTIALS_FILE']
      begin
        ENV['IMMICH_CREDENTIALS_FILE'] = file
        assert AmapCredentials.generate(folder)
        output = File.join(folder, '.generated/AMap.xcconfig')
        assert_equal 0600, File.stat(output).mode & 0777
        assert_includes File.read(output), AmapCredentials::BUNDLE_ID
        File.write(file, 'user=example')
        refute AmapCredentials.generate(folder)
        refute_includes File.read(output), 'c' * 32
      ensure
        ENV['IMMICH_CREDENTIALS_FILE'] = previous
      end
    end
  end
end
