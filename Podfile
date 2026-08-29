platform :ios, '12.0'
use_frameworks! :linkage => :static
inhibit_all_warnings!

project 'MezonChat.xcodeproj'

target 'MezonChat' do
  pod 'Texture', '~> 3.1.0'
  pod 'SQLCipher', '~> 4.0'
  pod 'FirebaseMessaging', '~> 10.0'
  pod 'MobileVLCKit', '~> 3.6.0'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      xcconfig_path = config.base_configuration_reference&.real_path
      next unless xcconfig_path && File.exist?(xcconfig_path)
      xcconfig = File.read(xcconfig_path)
      new_xcconfig = xcconfig.gsub(/-l"sqlite3"/, '')
      new_xcconfig = new_xcconfig.gsub(%r{"\$\(SDKROOT\)/usr/lib/libsqlite3\.tbd"}, '')
      File.open(xcconfig_path, 'w') { |f| f << new_xcconfig }

      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end
