# Cloud OAuth Setup

Direct Google Drive, OneDrive, and Box API integration requires OAuth app registrations.

The APK already contains the OAuth redirect handler and PKCE token exchange. Before sign-in will work, replace these placeholders in `app/src/main/res/values/strings.xml`:

- `google_drive_client_id`
- `onedrive_client_id`
- `box_client_id`

Use this redirect URI for all providers:

```text
syncmymobile://oauth
```

## Google Drive

Create an OAuth client in Google Cloud Console and enable the Google Drive API.

Recommended scope for broad download/sync:

```text
https://www.googleapis.com/auth/drive.readonly
```

Google treats broad Drive scopes as restricted. Public release may require Google verification and, depending on data handling, a security assessment.

## OneDrive

Create an Azure App Registration for Microsoft Graph.

Scopes used:

```text
offline_access Files.Read.All
```

The OneDrive API is accessed through Microsoft Graph with bearer tokens.

## Box

Create a Box Platform App with OAuth 2.0 enabled.

The app uses Box OAuth authorization and token endpoints. Box may require redirect URL configuration in the developer console.

## Current Implementation Status

- OAuth authorization URL generation.
- OAuth redirect handling.
- PKCE code challenge.
- Authorization-code token exchange.
- Access/refresh token storage in app preferences.

Next implementation step:

- In-app cloud browser for selecting Drive/OneDrive/Box folders and files via REST APIs.
- Cloud file streaming through the Android LAN HTTP server to the Windows desktop app.
