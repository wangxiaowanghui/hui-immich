require 'minitest/autorun'
require 'pathname'

class SigningConfigurationTest < Minitest::Test
  IOS = Pathname.new(__dir__).parent

  def configuration(identifier)
    content = IOS.join('Runner.xcodeproj/project.pbxproj').read
    block = content.match(/\t\t#{identifier} \/\* .*? \*\/ = \{(.*?)\n\t\t\};/m)
    refute_nil block, '目标构建配置必须存在'
    block[1]
  end

  def test_debug_and_profile_support_local_override_but_release_does_not
    assert_includes configuration('97C147061CF9000F007C117D'),
                    'CODE_SIGN_ENTITLEMENTS = "$(IMMICH_DEBUG_ENTITLEMENTS)";'
    assert_includes configuration('97C147071CF9000F007C117D'),
                    'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
    assert_includes configuration('249021D4217E4FDB00AE95B9'),
                    'CODE_SIGN_ENTITLEMENTS = "$(IMMICH_PROFILE_ENTITLEMENTS)";'
  end

  def test_default_keeps_full_permissions_before_local_override
    content = IOS.join('Signing.xcconfig').read
    local = content.index('#include? "Signing.local.xcconfig"')
    refute_nil local
    { 'DEBUG' => 'Runner.entitlements', 'PROFILE' => 'RunnerProfile.entitlements' }.each do |mode, file|
      default = content.index("IMMICH_#{mode}_ENTITLEMENTS = Runner/#{file}")
      refute_nil default
      assert_operator default, :<, local
    end
  end

  def test_profile_default_keeps_push_capability
    assert_includes IOS.join('Runner/RunnerProfile.entitlements').read, '<key>aps-environment</key>'
  end

  def test_full_entitlements_remain_available
    %w[Runner.entitlements RunnerProfile.entitlements].each do |name|
      content = IOS.join('Runner', name).read
      %w[com.apple.developer.associated-domains
         com.apple.developer.networking.wifi-info
         com.apple.security.application-groups].each do |capability|
        assert_includes content, "<key>#{capability}</key>"
      end
    end
  end
end
