#!/bin/zsh

# Xcode Cloud scripts

set -xeu
set -o pipefail

# list hardware
system_profiler SPSoftwareDataType SPHardwareDataType

# install rbenv
brew install rbenv
which ruby
echo 'eval "$(rbenv init -)"' >> ~/.zprofile
source ~/.zprofile
which ruby

rbenv install 3.0.3
rbenv global 3.0.3
ruby --version

# install bundle gem
gem install bundle

# setup gems
bundle install

bundle exec arkana
bundle exec pod install