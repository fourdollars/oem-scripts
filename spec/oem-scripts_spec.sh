#shellcheck shell=sh disable=SC2016,SC2004

Describe 'launchpad-api'
  Include ./launchpad-api
  It 'parse_api https://api.launchpad.net/devel/bugs/1'
    When call parse_api 'https://api.launchpad.net/devel/bugs/1'
    The output should equal 'https://api.launchpad.net/devel/bugs/1'
  End
  It 'parse_api /devel/bugs/1'
    When call parse_api '/devel/bugs/1'
    The output should equal 'https://api.launchpad.net/devel/bugs/1'
  End
  It 'parse_api devel/bugs/1'
    When call parse_api 'devel/bugs/1'
    The output should equal 'https://api.launchpad.net/devel/bugs/1'
  End
  It 'parse_api /bugs/1'
    When call parse_api '/bugs/1'
    The output should equal 'https://api.launchpad.net/devel/bugs/1'
  End
  It 'parse_api bugs/1'
    When call parse_api 'bugs/1'
    The output should equal 'https://api.launchpad.net/devel/bugs/1'
  End
End
