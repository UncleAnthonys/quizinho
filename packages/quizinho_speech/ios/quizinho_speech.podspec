Pod::Spec.new do |s|
  s.name             = 'quizinho_speech'
  s.version          = '0.1.0'
  s.summary          = "Quizinho's on-device speech recogniser with a custom player-name language model."
  s.homepage         = 'https://github.com/UncleAnthonys/quizinho'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Quizinho' => 'noreply@github.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'Speech', 'AVFoundation'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
