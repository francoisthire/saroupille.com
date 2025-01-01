# Deploying a website (almost for free)

This directory contains an executable to help you deploy a website for
free using Google Cloud Platform (GCP) and Cloudflare. Follow the
steps below to get started.

---

## Prerequisites

### 1. Set Up a GCP Account
1. Create a GCP account and set up a project.
2. Add a credit card to fund the GCP project (this is necessary, but you should not be charged).
   - GCP will notify you via email if a spending threshold is reached (this is enabled by default).
   - In practice, your deployment will use the Free Tier of GCP, so charges are unlikely (apart from potential minor charges of a few cents).

### 2. Install and Configure the `gcloud` Command
1. Install the `gcloud` CLI on your local machine.
2. Configure your GCP project:
   - Run `gcloud config configurations create website` to create a dedicated configuration for your website (replace `website` with a preferred name if desired).
   - Run `gcloud config set project <project_id>` where `<project_id>` is the identifier (not the name) of your GCP project.

### 3. Set Up a Cloudflare Account
1. Create a [Cloudflare account](https://dash.cloudflare.com/login).
2. Define and export the following environment variables:
   - `CLOUDFLARE_EMAIL`: Your Cloudflare account email.
   - `CLOUDFLARE_API_KEY`: Your Cloudflare API key (found in your Cloudflare account settings).
3. Configure your DNS so that Cloudflare takes ownership of the domain associated with your website.
   /!\ At the moment, the deployment script assumes there is a single project associated with your account

---

## Deployment Steps

1. Run the following command to create the VM:
   ```bash
   dune exec deploy/main.exe -- gcloud create vm -v
   ```
2. Update the Cloudflare DNS rules to redirect your domain to the IP address generated during the previous step:
   - The IP address can be found in the logs or via the GCP Console.

---

## TODO

- Provide more details about DNS registration.
- Add an explanation of why GCP won't charge the credit card for this setup.
- Enable Nginx in the Dockerfile configuration.



