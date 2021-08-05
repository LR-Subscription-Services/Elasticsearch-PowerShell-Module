#!/bin/bash
# Register the Microsoft RedHat Repo for PowerShell
sudo yum repolist | grep -q "packages-microsoft-com-prod"
if [ $? -eq 1 ]; then
    echo 'Microsoft YUM Repo is not currently installed.  Establishing microsoft yum repository.'
    curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
    if [ $? -eq 0 ]; then
        echo 'Successfully installed Microsoft YUM repository.'
    fi
fi

# Install PowerShell
which pwsh
if [ $? -eq 1 ]; then
    echo 'Microsoft PowerShell Core is not currently installed.  Running: sudo yum install -y powershell.'
    sudo yum install -y powershell
fi

# Update SSHD Config to support PowerShell SSH SubSystem to support PowerShell Remote Cmd over SSH
sudo grep -qxF 'Subsystem powershell /usr/bin/pwsh -sshs -NoLogo' /etc/ssh/sshd_config
if [ $? -eq 1 ]; then
    echo 'Subsystem powershell /usr/bin/pwsh -sshs -NoLogo' | sudo tee -a /etc/ssh/sshd_config
    if [ $? -eq 0 ]; then
        echo 'Successfully updated the ssh server configuration to support PowerShell Core subsystem.'
    else
        echo 'Unable to updated the ssh server configuration to support PowerShell Core subsystem.'
    fi

    # Restart SSHD service
    sudo systemctl restart sshd
    if [ $? -eq 0 ]; then
        echo 'PowerShell Core has successfully been installed and is available over SSH as a subsystem environment.'
    fi
else
    echo 'PowerShell Core was previously installed and configured for this environment.'
fi