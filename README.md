# LivingPortraitApp Instructions

## Overview

Welcome to the LivingPortraitApp project!

This application enables you to display videos using VLC media player integration on a Raspberry Pi.

<p align="center">
  <img src="https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/screenshots/Capture1.PNG" width="30%" />
  <img src="https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/screenshots/Capture2.PNG" width="30%" />
  <img src="https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/screenshots/Capture3.PNG" width="30%" />
</p>

---

## Prerequisites

- A Raspberry Pi (any model that supports VLC)
- VLC media player installed on the Raspberry Pi
- Basic familiarity with terminal commands
- Access to the internet for downloading files

---

## Installation

Using PuTTY (or any terminal), run the following command to install everything:  Full setup (first install or fresh system)

```bash
curl -sSL https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/setup_LivingPortraitApp_vlc.sh | bash
```


Using PuTTY (or any terminal), run the following command to Update only (skip system stuff, just update files)
```bash
curl -sSL https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/setup_LivingPortraitApp_vlc.sh | bash -s -- --update-only
```



Finish and reboot your Raspberry Pi for changes to take effect.
