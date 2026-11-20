# 从统一来源生成仅本机构建使用的配置；不执行 properties 内容，不输出凭据。
require 'fileutils'
require 'tempfile'
module AmapCredentials
  BUNDLE_ID = 'wang.xiaozhujia.immich'.freeze
  def self.read(path)
    return '' unless File.file?(path)
    fields = {}
    File.foreach(path, encoding: 'UTF-8') do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#', '!')
      key, value = line.split('=', 2)
      raise '统一凭据格式错误，未输出原始内容' if value.nil? || key.strip.empty?
      key = key.strip
      raise '统一凭据存在重复字段，未输出原始内容' if fields.key?(key)
      fields[key] = value.strip
    end
    # 沿用用户已提供的字段名；它的内容是 iOS SDK Key，而不是 Web 安全密钥。
    value = fields.fetch('AMAP_IOS_PASSCODE', '')
    raise 'iOS 地图 Key 格式无效，未输出原始内容' unless value.empty? || value.match?(/\A[0-9a-fA-F]{32}\z/)
    value
  end
  def self.generate(ios_root)
    override = ENV['IMMICH_CREDENTIALS_FILE']
    if override && (!override.start_with?('/') || !File.file?(override))
      raise 'IMMICH_CREDENTIALS_FILE 必须指向存在的绝对路径'
    end
    source = override || File.expand_path('../../../../user_info.properties', ios_root)
    key = read(source)
    folder = File.join(ios_root, '.generated')
    FileUtils.mkdir_p(folder, mode: 0700)
    destination = File.join(folder, 'AMap.xcconfig')
    raise '拒绝覆盖符号链接形式的地图配置' if File.symlink?(folder) || File.symlink?(destination)
    text = "// 自动生成，请只修改统一凭据来源。\nAMAP_IOS_KEY = #{key}\nAMAP_IOS_BUNDLE_ID = #{BUNDLE_ID}\n"
    Tempfile.create(['amap-', '.xcconfig'], folder) do |file|
      file.chmod(0600)
      file.write(text)
      file.close
      File.rename(file.path, destination)
    end
    !key.empty?
  end
end
if $PROGRAM_NAME == __FILE__
  begin
    configured = AmapCredentials.generate(File.expand_path('..', __dir__))
    puts configured ? 'iOS 地图本地配置已生成，凭据未回显' : '未配置 iOS 地图 Key，将使用备用地图'
  rescue StandardError => error
    warn error.message
    exit 1
  end
end
