# rclone-backup

My personal rclone script to faciliate backing up my devices to the cloud.

Works on both Linux and Mac

## Install rclone

```bash
# https://rclone.org/install/
# Linux
curl https://rclone.org/install.sh | sudo bash

# Mac
brew install rclone
```

## Specific Requirements for Mac

```bash
# Install GNU core utilities (those that come with macOS are outdated).
# Don’t forget to add `$(brew --prefix coreutils)/libexec/gnubin` to `$PATH`.
brew install coreutils

# Install GNU `grep`
brew install grep

# Install flock
brew install discoteq/discoteq/flock
```
