# Launch setup: domain, Google sign-in, email

The app code is already done. This is the one-time setup you do in other dashboards, **all at once**, when you have your domain. Nothing here needs a code change or redeploy.

- The Google sign-in button appears **by itself** once Google is switched on in Supabase. The app reads which providers are enabled.
- Google and email codes go into **Supabase**, never into the app code or GitHub.

---

## 0. Collect these as you go

| # | Detail | Where you get it | Where it goes |
|---|---|---|---|
| 1 | Your domain, e.g. `yourdomain.com` | Domain registrar | Vercel, Supabase, Google, email provider |
| 2 | App address, e.g. `app.yourdomain.com` | You choose | Vercel (step 1), Supabase (step 2), Google (step 3) |
| 3 | Google **Client ID** | Google Cloud (step 3) | Supabase → Google provider |
| 4 | Google **Client secret** | Google Cloud (step 3) | Supabase → Google provider |
| 5 | Privacy policy URL | Your website | Google consent screen |
| 6 | SMTP host / port / username / password | Brevo or Resend (step 4) | Supabase → SMTP settings |
| 7 | Sender email, e.g. `no-reply@yourdomain.com` | You choose | Supabase → SMTP settings |

Fixed values you'll need (copy exactly):
- **Supabase project URL:** `https://iwpfhalextbzbvcajtxu.supabase.co`
- **Google redirect URI (callback):** `https://iwpfhalextbzbvcajtxu.supabase.co/auth/v1/callback`
- **Current app address:** `https://map-trainer-six.vercel.app`

> ⚠️ This Supabase project is **shared with your other apps**. Never change **Authentication → URL Configuration → Site URL**; it belongs to another app. Only *add* Redirect URLs. Custom SMTP (step 4) changes the sender for **every** app's auth emails in this project.

---

## 1. Point your domain at the app (Vercel) — about 5 minutes

1. Vercel → project **map-trainer** → **Settings → Domains → Add**, then enter `app.yourdomain.com`.
2. Vercel shows a DNS record, usually a **CNAME** `app` → `cname.vercel-dns.com`. Add it at your domain registrar.
3. Wait until Vercel shows **Valid Configuration**. The old `map-trainer-six.vercel.app` keeps working too.
4. **On your sales website:** add a button "Open the app" linking to `https://app.yourdomain.com`.

## 2. Supabase: allow the new address — about 2 minutes

Supabase → **Authentication → URL Configuration → Redirect URLs → Add URL**:
- `https://app.yourdomain.com/**`
- Keep the existing `https://map-trainer-six.vercel.app/**`.
- **Do not touch Site URL.**

## 3. Google sign-in — about 15 minutes, free

The Google Cloud project and the sign-in client are free: no billing account or card is needed.

1. Go to <https://console.cloud.google.com> and create a project, e.g. **MAP Trainer**.
2. **APIs & Services → OAuth consent screen** (on newer consoles: **Google Auth Platform → Branding / Audience**):
   - **User type:** External.
   - **App name**, **support email**, and **app logo** (optional; adding a logo can trigger Google's brand review).
   - **App home page:** `https://app.yourdomain.com` (or your website).
   - **Privacy policy URL:** detail #5. Required before going live, and important for a children's app.
   - **Authorized domains:** `yourdomain.com`.
   - **Scopes:** only the basic `openid`, `email`, `profile`. These don't need Google's security review.
   - **Publishing status:** "Testing" allows only listed test users (up to 100). Click **Publish app → In production** when ready.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID:**
   - **Application type:** Web application.
   - **Authorized JavaScript origins:**
     - `https://app.yourdomain.com`
     - `https://map-trainer-six.vercel.app`
   - **Authorized redirect URIs:** `https://iwpfhalextbzbvcajtxu.supabase.co/auth/v1/callback`
   - **Create**, then copy the **Client ID** (#3) and **Client secret** (#4).
4. Supabase → **Authentication → Providers (Sign In / Providers) → Google** → enable, paste the Client ID and secret → **Save**.
5. Open the app → **Sign in**. **Continue with Google** should now be visible. Test it once.

**Schools using Google Workspace for Education:** the school's Google admin may need to allow the app. In the Admin console, that's **Security → API controls → App access control** (search for your app name or Client ID). This is common for under-18 accounts, so mention it in your school onboarding email.

**Optional, Microsoft sign-in:** Supabase provider **Azure**. Register an app in Microsoft Entra ID with the same Supabase callback URL, then paste its ID and secret into Supabase → Azure. The **Continue with Microsoft** button appears automatically.

## 4. Email that reaches inboxes (custom SMTP) — about 20 minutes, free tier

Pick one provider. Free limits as last checked, so confirm on their pricing page:
- **Brevo:** about 300 emails a day.
- **Resend:** about 3,000 a month, 100 a day.

1. Create an account and **add your domain**.
2. Add the DNS records they show at your registrar: **SPF**, **DKIM** and ideally **DMARC**. Wait for "verified".
3. Get the **SMTP settings** (#6).
   - Brevo: `smtp-relay.brevo.com`, port `587`, your login plus an SMTP key.
   - Resend: `smtp.resend.com`, port `465` or `587`, username `resend`, password is an API key.
4. Supabase → **Authentication → Emails → SMTP Settings → Enable custom SMTP**:
   - sender email (#7) and sender name, e.g. **MAP Trainer**;
   - host, port, username, password (#6) → **Save**.
5. Supabase → **Authentication → Rate Limits:** raise **emails per hour** to fit your provider (e.g. 100).
6. Optional: Supabase → **Authentication → Emails → Templates → Magic Link**. Adjust the wording, and keep the `{{ .ConfirmationURL }}` link.
7. Send yourself a sign-in link from the app and check it arrives in the **inbox**, not spam.

## 5. Final check (10 minutes)

- [ ] `https://app.yourdomain.com` opens the app, and it installs as an app on a phone.
- [ ] **Continue with Google** signs in and returns to the app; the name box fills in automatically.
- [ ] An emailed sign-in link arrives in the inbox and signs in.
- [ ] Classes, leaderboards and live sessions work while signed in with Google.
- [ ] Tell Claude the final domain, so `CLAUDE.md` gets updated. The production URL and the Supabase redirect list are recorded there.
