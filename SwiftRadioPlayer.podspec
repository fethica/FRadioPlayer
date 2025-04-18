#
# Be sure to run `pod lib lint SwiftRadioPlayer.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SwiftRadioPlayer'
  s.version          = '0.1.22'
  s.summary          = 'A radio player for iOS/macOS/tvOS'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
SwiftRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.
Forked from FRadioPlayer.
                       DESC

  s.homepage         = 'https://github.com/dehy/SwiftRadioPlayer'
  s.screenshots     = 'https://fethica.com/assets/img/web/swiftradioplayer-example.png'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Fethi El Hassasna' => 'e.fethi.c@gmail.com', 'Arnaud de Mouhy' => 'arnaud@flyingpingu.com' }
  s.source           = { :git => 'https://github.com/dehy/SwiftRadioPlayer.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.12'
  s.tvos.deployment_target = '10.0'
  s.swift_version = '5.0'
  s.source = { :git => 'https://github.com/dehy/SwiftRadioPlayer.git', :tag => s.version.to_s }
  s.source_files = 'Sources/**/*.swift'

  # s.resource_bundles = {
  #   'SwiftRadioPlayer' => ['Sources/SwiftRadioPlayer/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
