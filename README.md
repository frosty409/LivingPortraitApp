# LivingPortraitApp Instructions

## Overview

Welcome to the LivingPortraitApp project!

This application enables you to display videos using VLC media player integration on a Raspberry Pi.

---

## Prerequisites

- A Raspberry Pi (any model that supports VLC)
- VLC media player installed on the Raspberry Pi
- Basic familiarity with terminal commands
- Access to the internet for downloading files

---

## Installation

Using PuTTY (or any terminal), run the following command to install everything:

```bash
curl -sSL https://raw.githubusercontent.com/jdesign21/LivingPortraitApp/refs/heads/main/setup_LivingPortraitApp_vlc.sh | bash
```

1. Log in to your Raspberry Pi.
2. Run this command to open the Raspberry Pi configuration tool:

```bash
sudo raspi-config
```

Navigate to System Options > Boot / Auto Login.

Select Console (text) login or Console Autologin depending on your preference.

Finish and reboot your Raspberry Pi for changes to take effect.
