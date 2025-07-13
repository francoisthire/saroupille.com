open Tezt
include Base

module Cli = struct
  let section =
    Clap.section ~description:"Arguments for deploying website" "deployment"

  (* Cloudflare supports tokens, but I had a hard time to configure it properly.
     Hence we are using an API key and an address mail for authentification.
  *)
  let cloudflare_api_key =
    Clap.default_string ~section
      ~description:
        "Your Cloudflare API key (can be provided via the environment variable \
         'CLOUDFLARE_API_KEY')"
      ~long:"cloudflare-api-key"
    @@
    match Sys.getenv_opt "CLOUDFLARE_API_KEY" with
    | None -> ""
    | Some value -> value

  let cloudflare_api_mail =
    Clap.default_string ~section
      ~description:
        "Your Cloudflare email (can be provided via the environment variable \
         'CLOUDFLARE_EMAIL')"
      ~long:"cloudflare-email"
    @@
    match Sys.getenv_opt "CLOUDFLARE_EMAIL" with
    | None -> ""
    | Some value -> value

  let vm_name =
    Clap.default_string ~section ~description:"Gcloud name of the VM"
      ~long:"vm-name" "website"

  let project_id =
    Clap.optional_string ~section
      ~description:
        "Your GCP project id (default is to get it from 'gcloud config \
         get-value project)"
      ~long:"project-id" ()
end

module Cloudflare = struct
  (* Wrap an API call with authentification header. *)
  let with_auth ?(meth = "GET") ?data path =
    let mail =
      if Cli.cloudflare_api_mail = "" then
        Test.fail "Please specify your cloudflare mail with '--mail'"
      else Cli.cloudflare_api_mail
    in
    let key =
      if Cli.cloudflare_api_key = "" then
        Test.fail "Please specify your cloudflare global key with '--key'"
      else Cli.cloudflare_api_key
    in
    let* output =
      Process.run_and_read_stdout "curl"
      @@ [
           "-X";
           meth;
           path;
           "-H";
           Format.asprintf "X-Auth-Email: %s" mail;
           "-H";
           Format.asprintf "X-Auth-Key: %s" key;
           "-H";
           "Content-Type: application/json";
         ]
      @ match data with None -> [] | Some data -> [ "--data"; data ]
    in
    Lwt.return (JSON.parse ~origin:"with_token" output)

  let get_zone () = with_auth "https://api.cloudflare.com/client/v4/zones"

  let get_zone_id =
    let cache = ref None in
    fun () ->
      match !cache with
      | Some zone_id -> Lwt.return zone_id
      | None ->
          let* json = get_zone () in
          let results = JSON.(json |-> "result" |> as_list) in
          let result =
            match results with
            | [ result ] -> result
            | _ ->
                Test.fail
                  "Deployment only support the case where there is one zone id \
                   at the moment"
          in
          let zone_id = JSON.(result |-> "id" |> as_string) in
          cache := Some zone_id;
          Lwt.return zone_id

  let get_pagerules () =
    let* zone_id = get_zone_id () in
    with_auth
    @@ Format.asprintf "https://api.cloudflare.com/client/v4/zones/%s/pagerules"
         zone_id

  let pagerules_data =
    {|
{
    "targets": [
      {
        "target": "url",
        "constraint": {
          "operator": "matches",
          "value": "*saroupille.com/*"
        }
      }
    ],
    "actions": [
      {
        "id": "cache_level",
        "value": "cache_everything"
      },
      {
        "id": "edge_cache_ttl",
        "value": 604800
      }
    ],
    "priority": 1,
    "status": "active"
  }
|}

  let post_pagerules () =
    let* zone_id = get_zone_id () in
    with_auth ~meth:"POST" ~data:pagerules_data
    @@ Format.asprintf "https://api.cloudflare.com/client/v4/zones/%s/pagerules"
         zone_id

  let get_dns_records () =
    let* zone_id = get_zone_id () in
    let* _ =
      with_auth ~meth:"GET"
      @@ Format.asprintf
           "https://api.cloudflare.com/client/v4/zones/%s/dns_records" zone_id
    in
    Lwt.return_unit

  let post_purge_cache () =
    let* zone_id = get_zone_id () in
    let* _ =
      with_auth ~meth:"POST" ~data:{|{"purge_everything": true}|}
      @@ Format.asprintf
           "https://api.cloudflare.com/client/v4/zones/%s/purge_cache" zone_id
    in
    Lwt.return_unit

  (* Fetch the Cloudflare IP ranges using curl *)
  let fetch_cloudflare_ips () =
    let open Lwt.Syntax in
    let* output =
      Process.run_and_read_stdout "curl"
        [ "-s"; "https://api.cloudflare.com/client/v4/ips" ]
    in
    let json = JSON.parse ~origin:"cloudflare-ips" output in
    let ipv4s =
      JSON.(json |-> "result" |-> "ipv4_cidrs" |> as_list |> List.map as_string)
    in
    let ipv6s =
      JSON.(json |-> "result" |-> "ipv6_cidrs" |> as_list |> List.map as_string)
    in
    Lwt.return (ipv4s, ipv6s)
end

module Gcloud = struct
  let project_id =
    let cache = ref None in
    fun () ->
      match !cache with
      | Some project_id -> Lwt.return project_id
      | None -> (
          match Cli.project_id with
          | Some project_id ->
              cache := Some project_id;
              Lwt.return project_id
          | None ->
              let* project_id =
                Process.run_and_read_stdout "gcloud"
                  [ "config"; "get-value"; "project" ]
              in
              let project_id = String.trim project_id in
              cache := Some project_id;
              Lwt.return project_id)

  let docker_uri () =
    let* project_id = project_id () in
    Lwt.return (Format.asprintf "gcr.io/%s/website:latest" project_id)

  (* These parameters are necessary to qualify for the free tier as defined by GCP:
           https://cloud.google.com/free/docs/free-cloud-features#compute
  *)
  let zone = "us-central1-c"
  let machine_type = "e2-micro"
  let no_preemptible = "--no-preemptible"

  let compute_instance_create () =
    let* project_id = project_id () in
    let* docker_uri = docker_uri () in
    (* These parameters specify the use of a Container-Optimized OS. *)
    let image_family = "cos-stable" in
    let image_project = "cos-cloud" in
    let startup_script =
      Format.asprintf
        {|
    #!/bin/bash
    # Authenticate Docker with Google Cloud Registry
    docker-credential-gcr configure-docker
        
    # Pull and run the Docker container
    docker pull %s
    docker run --rm -d --name website -p 80:8080 %s
    |}
        docker_uri docker_uri
    in
    Process.run "gcloud"
      [
        "compute";
        "instances";
        "create";
        Cli.vm_name;
        "--zone";
        zone;
        "--machine-type";
        machine_type;
        (* Free-tier machine type *)
        "--image-family";
        image_family;
        (* Using stable Container-Optimized OS *)
        "--image-project";
        image_project;
        (* The GCP project hosting the COS images *)
        "--service-account";
        (* Service account to authenticate Docker and manage resources *)
        Format.asprintf "docker-access-sa@%s.iam.gserviceaccount.com" project_id;
        "--metadata";
        (* Pass the startup script to initialize the VM at boot *)
        Format.asprintf "startup-script=%s" startup_script;
        "--tags";
        "http-server";
        (* Apply network tags for HTTP traffic access *)
        "--scopes";
        "https://www.googleapis.com/auth/cloud-platform";
        (* Allow full API access to cloud resources *)
        no_preemptible;
        (* Ensure the instance is not preemptible *)
      ]

  let compute_instance_delete () =
    Process.run "gcloud"
      [
        "compute"; "instances"; "delete"; Cli.vm_name; "--zone"; zone; "--quiet";
      ]

  (* This command can be used to connect on the VM via SSH. Gcloud does the key management for you. *)
  let compute_ssh ?command () =
    Process.run "gcloud"
    @@ [ "compute"; "ssh"; "website"; "--zone"; "us-central1-c" ]
    @ match command with None -> [] | Some command -> [ "--" ] @ command

  let projects_add_iam_policy_binding () =
    let* project_id = project_id () in
    Process.run "gcloud"
      [
        "projects";
        "add-iam-policy-binding";
        project_id;
        "--member";
        Format.asprintf
          "serviceAccount:docker-access-sa@%s.iam.gserviceaccount.com"
          project_id;
        "--role";
        "roles/artifactregistry.reader";
      ]

  let services_enable () =
    Process.run "gcloud" [ "services"; "enable"; "compute.googleapis.com" ]

  let compute_firewall_rules_create_or_update_allow ~rule_name ~ranges =
    let* project_id = project_id () in
    let allowed_ips_arg = String.concat "," ranges in
    let command mode =
      [
        "compute";
        "firewall-rules";
        mode;
        rule_name;
        "--project";
        project_id;
        "--source-ranges";
        allowed_ips_arg;
        "--allow";
        "tcp:80,tcp:443";
        "--priority";
        "1000";
        "--quiet";
      ]
    in
    let process = Process.spawn "gcloud" (command "update") in
    let* status = Process.wait process in
    match status with
    | WEXITED 0 -> Lwt.return_unit
    | _ -> Process.run "gcloud" (command "create")

  let compute_firewall_rules_deny ~rule_name =
    let* project_id = project_id () in
    let command mode =
      [ "compute"; "firewall-rules"; mode; rule_name; "--project"; project_id ]
      @ (if mode = "create" then [ "--action"; "DENY" ] else [])
      @ [ "--rules"; "tcp:80,tcp:443"; "--priority"; "2000"; "--quiet" ]
    in
    let process = Process.spawn "gcloud" (command "update") in
    let* status = Process.wait process in
    match status with
    | WEXITED 0 -> Lwt.return_unit
    | _ -> Process.run "gcloud" (command "create")

  let firewall_only_allows_cloudflare () =
    let* ipv4s, ipv6s = Cloudflare.fetch_cloudflare_ips () in
    let ipv4_rule_name = "allow-cloudflare-only-ipv4" in
    let ipv6_rule_name = "allow-cloudflare-only-ipv6" in
    let* () =
      compute_firewall_rules_create_or_update_allow ~rule_name:ipv4_rule_name
        ~ranges:ipv4s
    in
    let* () =
      compute_firewall_rules_create_or_update_allow ~rule_name:ipv6_rule_name
        ~ranges:ipv6s
    in
    compute_firewall_rules_deny ~rule_name:"deny-all"
end

let () =
  Test.register ~__FILE__ ~title:"Set cache rule for cloudflare"
    ~tags:[ "cloudflare"; "cache"; "set" ]
  @@ fun () ->
  (* Not sure to understanding properly the difference between cache rules and
     page rules. It seems page rules does the job though. *)
  let* _ = Cloudflare.post_pagerules () in
  (* let* _ = Gcloud.compute_instance_create () in *)
  Lwt.return_unit

let () =
  Test.register ~__FILE__ ~title:"Get Cloudflare cache rule"
    ~tags:[ "cloudflare"; "cache"; "get" ]
  @@ fun () ->
  let* _ = Cloudflare.get_pagerules () in
  Lwt.return_unit

let () =
  Test.register ~__FILE__ ~title:"Get Cloudflare IPs"
    ~tags:[ "cloudflare"; "ips" ]
  @@ fun () ->
  let* _ = Cloudflare.fetch_cloudflare_ips () in
  Lwt.return_unit

let () =
  Test.register ~__FILE__ ~title:"Gcloud update firewall rules for Cloudflare"
    ~tags:[ "gcloud"; "cloudflare"; "firewall"; "update" ]
  @@ fun () -> Gcloud.firewall_only_allows_cloudflare ()

let () =
  Test.register ~__FILE__ ~title:"Enabling gcloud services API"
    ~tags:[ "gcloud"; "service"; "enable" ]
  @@ fun () -> Gcloud.services_enable ()

let () =
  Test.register ~__FILE__ ~title:"Create service account"
    ~tags:[ "gcloud"; "service"; "account"; "create" ]
  @@ fun () -> Gcloud.projects_add_iam_policy_binding ()

let () =
  Test.register ~__FILE__ ~title:"Deploy Gcloud VM"
    ~tags:[ "gcloud"; "deploy"; "vm"; "create" ]
  @@ fun () ->
  let* _ = Cloudflare.post_pagerules () in
  let* () = Gcloud.services_enable () in
  let* () = Gcloud.projects_add_iam_policy_binding () in
  let* () = Process.run "gcloud" [ "auth"; "configure-docker" ] in
  let* docker_uri = Gcloud.docker_uri () in
  let* () = Process.run "docker" [ "build"; "-t"; docker_uri; "." ] in
  let* () = Process.run "docker" [ "push"; docker_uri ] in
  let* () = Gcloud.compute_instance_create () in
  let* () = Gcloud.firewall_only_allows_cloudflare () in
  Log.warn "Be sure your DNS records on Cloudflare are up to date";
  Lwt.return_unit

let () =
  Test.register ~__FILE__ ~title:"Destroy Gcloud VM"
    ~tags:[ "gcloud"; "vm"; "destroy"; "delete" ]
  @@ fun () -> Gcloud.compute_instance_delete ()

let () =
  Test.register ~__FILE__ ~title:"Purge cache"
    ~tags:[ "cloudflare"; "purge"; "cache" ]
  @@ fun () -> Cloudflare.post_purge_cache ()

let () =
  Test.register ~__FILE__ ~title:"Get DNS records"
    ~tags:[ "cloudflare"; "dns"; "records" ]
  @@ fun () -> Cloudflare.get_dns_records ()

let () =
  Test.register ~__FILE__ ~title:"Update the docker image on the Gcloud VM"
    ~tags:[ "gcloud"; "vm"; "update" ]
  @@ fun () ->
  let* () = Process.run "gcloud" [ "auth"; "configure-docker" ] in
  let* docker_uri = Gcloud.docker_uri () in
  let* () = Process.run "docker" [ "build"; "-t"; docker_uri; "." ] in
  let* () = Process.run "docker" [ "push"; docker_uri ] in
  (* FIXME: Before stopping the website, ensure the docker run command works. *)
  let* () = Gcloud.compute_ssh ~command:[ "docker"; "stop"; "website" ] () in
  let* () = Gcloud.compute_ssh ~command:[ "docker"; "pull"; docker_uri ] () in
  let* () =
    Gcloud.compute_ssh
      ~command:
        [
          "docker";
          "run";
          "--rm";
          "-d";
          "--name";
          "website";
          "-p";
          "80:8080";
          (* The website runs on 8080 within the docker container, but we want to run on port 80 on the VM. *)
          docker_uri;
        ]
      ()
  in
  (* We purge the cache so that updates take effect immediatly *)
  Cloudflare.post_purge_cache ()

let () = Test.run ()
