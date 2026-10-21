# ReceiptDrive — Privacy Policy

**Effective date:** October 21, 2026

ReceiptDrive ("the app") is made by Lai Kong Fung ("we"). This policy explains what happens to your information when you use the app on iPhone or iPad. In short: **we don't run any servers, we don't collect your data, and your receipts stay on your device** unless you choose to send them somewhere.

## What the app stores, and where

Everything you enter stays **on your iPhone or iPad**, in the app's own storage:

- receipts (date, merchant, amount, description, category, group, note)
- receipt photos and PDF pages
- your categories, groups and settings

API keys you enter for AI scanning are kept in the **iOS Keychain** on your device.

We have no account system, no analytics, no advertising and no tracking. We never receive, see or sell your data.

## When information leaves your device

Information only leaves your device when **you** use one of these features:

### 1. AI receipt scanning (optional)

To fill in receipt details automatically, the app can send the **receipt photo or PDF pages you are scanning** to the AI provider you choose in Settings → Receipt Scanning:

- **Anthropic** (Claude) — [privacy policy](https://www.anthropic.com/legal/privacy)
- **OpenAI** — [privacy policy](https://openai.com/policies/privacy-policy)
- **Google** (Gemini) — [privacy policy](https://policies.google.com/privacy)

- The app **asks your permission** before anything is sent to a provider, and you can turn this off anytime in Settings → Receipt Scanning ("Allow sending receipts to …").
- Images are sent **directly from your device to the provider** using **your own API key**, over an encrypted connection. They do not pass through us.
- They are sent only when you scan a receipt, and only to read its date, merchant, total and items.
- How long a provider keeps the data is governed by **your agreement with that provider** and its privacy policy linked above.

If you don't add an API key or don't allow sending, nothing is sent; you can still enter receipts by hand.

### 2. Google Drive upload (optional)

Google Drive is optional. The app asks to sign in to Google only if you tap "Connect to Google Drive" in Settings.

- **What the app requests:** the `drive.file` permission (Google's narrowest Drive permission) and your basic Google profile.
- **How it is used:** when you tap "Upload to Drive", the app creates a "ReceiptDrive" folder in your Drive (the first time) and uploads that receipt's photo or PDF into it. With `drive.file`, the app can only see and change files it created itself. It cannot read, list or change any of your other Drive files.
- **Your email address** is shown in Settings so you know which account is connected. It is not sent anywhere else.
- **Nothing is uploaded automatically.** Files go to Drive only when you tap "Upload to Drive".
- Your Google sign-in is stored on your device. We have no server, so Google user data is never sent to us, stored by us, shared, sold, or used for advertising or AI training.
- You can disconnect anytime in Settings, or remove the app's access at [myaccount.google.com/permissions](https://myaccount.google.com/permissions).

ReceiptDrive's use and transfer of information received from Google APIs will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. Google's handling of your files is covered by the [Google privacy policy](https://policies.google.com/privacy).

### 3. Web Access over Wi-Fi (optional)

When you turn on Web Access in Settings, the app runs a small web server **on your local Wi-Fi network** so a computer on the same network can open the app's web version. A new 4-digit code is required each time it's turned on. Nothing goes over the internet through this feature, and it stops when you turn it off.

### 4. Sharing and exporting

When you export (CSV, PDF), share a receipt PDF, or save a photo to your Photos library, the file goes wherever **you** choose in the iOS share sheet.

## Permissions the app asks for

- **Camera** — to photograph receipts.
- **Photos (add only)** — to save a receipt photo when you tap "Save to Photos".
- **Local network** — only for Web Access over Wi-Fi.

## Deleting your data

- Delete a receipt in the app to remove it from your device.
- Deleting the app removes all of its data from your device.
- Remove an API key or turn off AI sending in Settings → Receipt Scanning.
- Data you sent to an AI provider or to Google Drive is held by that service; manage or delete it with them.

## Children

The app is not directed at children under 13 and does not knowingly collect information from them.

## Changes to this policy

If this policy changes, we'll update this page and the effective date above.

## Contact

Questions about this policy: mobile_fung@hotmail.com
