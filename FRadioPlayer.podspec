#
# Be sure to run `pod lib lint FRadioPlayer.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'FRadioPlayer'
  s.version          = '0.1.10'
  s.summary          = 'A radio player for iOS'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
FRadioPlayer is a wrapper around AVPlayer to handle internet radio playback.
                       DESC

  s.homepage         = 'https://github.com/fethica/FRadioPlayer'
  s.screenshots     = 'https://fethica.com/img/web/fradioplayer-example.png'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Fethi El Hassasna' => 'e.fethi.c@gmail.com' }
  s.source           = { :git => 'https://github.com/fethica/FRadioPlayer.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/fethica'

  s.ios.deployment_target = '9.0'
  s.source = { :git => 'https://github.com/fethica/FRadioPlayer.git', :tag => s.version.to_s }
  s.source_files = 'Source/*.swift'

  # s.resource_bundles = {
  #   'FRadioPlayer' => ['FRadioPlayer/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
