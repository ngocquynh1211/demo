@echo off
set vclipath=%1
set perlpath=%2
set dclipath=%vclipath:perl\bin=VMware DCLI%
set path=%path%;%vclipath%;%perlpath%;%dclipath%
IF "%PERL5LIB%"=="" (setx PERL5LIB /K HKEY_CURRENT_USER\Environment\PERL5LIB)



