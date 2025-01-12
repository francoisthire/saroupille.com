module JSON = Tezt.JSON

module Configuration = struct
  (** Defines general configuration parameters for the website. *)

  type t = { title : string }

  let default = { title = "Website title" }

  let configuration =
    match Assets.read "configuration.json" with
    | None -> default
    | Some content ->
        let json = JSON.parse ~origin:"configuration.json" content in
        let title = JSON.(json |-> "title" |> as_string) in
        { title }
end

let configuration = Configuration.configuration

module About = struct
  (** Defines the content of the about page. *)

  type t = {
    image : string option;
    alt : string option;
    title : string;
    subtitle : string option;
    description : string;
  }

  let default =
    {
      image = None;
      alt = None;
      title = "Author";
      subtitle = None;
      description = "No description yet";
    }

  let filename = "about.json"

  let about =
    match Assets.read filename with
    | None -> default
    | Some content ->
        let json = JSON.parse ~origin:filename content in
        let image = JSON.(json |-> "image" |> as_string_opt) in
        let alt = JSON.(json |-> "alt" |> as_string_opt) in
        let title = JSON.(json |-> "title" |> as_string) in
        let subtitle = JSON.(json |-> "subtitle" |> as_string_opt) in
        let description = JSON.(json |-> "description" |> as_string) in
        { image; alt; title; subtitle; description }

  let html =
    let open Dream_html in
    let open HTML in
    let alt_text = Option.value ~default:"" about.alt in
    let figure =
      match about.image with
      | Some source ->
          [
            figure
              [ class_ "about-image" ]
              [ img [ src "%s" source; alt "%s" alt_text ] ];
          ]
      | None -> []
    in
    [
      section
        [ class_ "about-section" ]
        ([
           div
             [ class_ "about-text" ]
             [
               h3 [] [ txt "%s" about.title ];
               (match about.subtitle with
               | None -> null []
               | Some subtitle -> h5 [] [ txt "%s" subtitle ]);
               p [] [ txt ~raw:true "%s" about.description ];
             ];
         ]
        @ figure);
    ]
end

module News = struct
  (** Define the content of the news section. *)

  type kind = Post of { filename : string } | Other

  type item = {
    date : string;
    title : string;
    description : string;
    kind : kind;
  }

  type t = item list [@@warning "-34"]

  let filename = "news.json"

  let news =
    let item_of_json item =
      let date = JSON.(item |-> "date" |> as_string) in
      let title = JSON.(item |-> "title" |> as_string) in
      let description = JSON.(item |-> "description" |> as_string) in
      let kind =
        match JSON.(item |-> "kind" |> as_string) with
        | "post" ->
            let filename = JSON.(item |-> "filename" |> as_string) in
            Post { filename }
        | _ -> Other
      in
      { date; title; description; kind }
    in
    match Assets.read filename with
    | None -> []
    | Some content ->
        let json = JSON.parse ~origin:filename content in
        JSON.(json |> as_list |> List.map item_of_json)

  let item_to_html ?(filter = fun _ -> true)
      ({ date; title = news_title; description; kind = news_kind } as item) =
    let open Dream_html in
    let open HTML in
    let title =
      match news_kind with
      | Other -> [ txt " %s" news_title ]
      | Post { filename } ->
          [ a [ href "%s" filename ] [ txt " > %s" news_title ] ]
    in
    if filter item then
      [
        dt [] [ time [ datetime "%s" date ] [ txt "%s" date; em [] title ] ];
        dd [] [ txt "%s" description ];
      ]
    else []

  (* To print on the home page. *)
  let html_short =
    let open Dream_html in
    let open HTML in
    let size = List.length news in
    let limit = 5 in
    if size = 0 then [ txt "No news" ]
    else if size <= limit then
      [ dl [] @@ (List.map item_to_html news |> List.concat) ]
    else
      let first_news = List.to_seq news |> Seq.take limit |> List.of_seq in
      [
        dl [] @@ (List.map item_to_html first_news |> List.concat);
        a [ href "/news" ] [ txt "See more" ];
      ]

  (* To print on the news page. *)
  let html =
    let open Dream_html in
    let open HTML in
    let size = List.length news in
    if size = 0 then [ txt "No news" ]
    else [ dl [] @@ (List.map item_to_html news |> List.concat) ]

  (* To print on the archive page. *)
  let post_html =
    let open Dream_html in
    let open HTML in
    let size = List.length news in
    let filter { kind; _ } =
      match kind with Post _ -> true | Other -> false
    in
    if size = 0 then [ txt "No news" ]
    else [ dl [] @@ (List.map (item_to_html ~filter) news |> List.concat) ]
end

module Softwares = struct
  (** Define the content of the software section. *)

  type item = { name : string; description : string; url : string }
  type t = item list [@@warning "-34"]

  let filename = "software.json"

  let softwares =
    let item_of_json item =
      let name = JSON.(item |-> "name" |> as_string) in
      let description = JSON.(item |-> "description" |> as_string) in
      let url = JSON.(item |-> "url" |> as_string) in
      { name; description; url }
    in
    match Assets.read filename with
    | None -> []
    | Some content ->
        let json = JSON.parse ~origin:filename content in
        JSON.(json |> as_list |> List.map item_of_json)

  let item_to_html { name = software_name; description; url } =
    let open Dream_html in
    let open HTML in
    [
      dt [] [ a [ href "%s" url ] [ em [] [ txt "> %s" software_name ] ] ];
      dd [] [ txt "%s" description ];
    ]

  let html =
    let open Dream_html in
    let open HTML in
    let size = List.length softwares in
    if size = 0 then [ txt "No software" ]
    else [ dl [] @@ (List.map item_to_html softwares |> List.concat) ]
end

module Head = struct
  let html =
    let open Dream_html in
    let open HTML in
    [
      meta [ charset "utf-8" ];
      title [] "%s" configuration.Configuration.title;
      (* Useful for supporting smartphones. *)
      meta [ name "viewport"; content "width=device-width" ];
      (* Default CSS uses Sakura them:
       https://github.com/oxalorg/sakura
   *)
      link
        [
          rel "stylesheet";
          href "https://cdn.jsdelivr.net/npm/sakura.css/css/sakura.css";
          type_ "text/css";
          media "screen";
        ];
      link
        [
          rel "stylesheet";
          href "https://unpkg.com/sakura.css/css/sakura-dark.css";
          type_ "text/css";
          media "screen and (prefers-color-scheme: dark)";
        ];
      link
        [
          rel "stylesheet";
          href
            "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/styles/default.min.css";
          type_ "text/css";
        ];
      script
        [
          src
            "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/highlight.min.js";
        ]
        "";
      script
        [
          src
            "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/languages/ocaml.min.js";
        ]
        "";
      script [] "hljs.highlightAll()";
      (* Sakura CSS can be overrided by ad-hoc classes. They are listed below. *)
      link [ rel "stylesheet"; href "/assets/about.css"; type_ "text/css" ];
    ]
end

type route =
  | Home
  | About
  | Archive
  | News
  | Software
  | Post of { filename : string }
(* A blog post is referenced by a filename. *)

module Header = struct
  let html route =
    let open Dream_html in
    let open HTML in
    [
      nav []
        [
          div
            (* We want the top navigation menu to be on the right. In
                          the future, it may have its own CSS class. *)
            [ style_ "text-align: right" ]
            [
              (* A bit ugly, at some point, we may refactor this. *)
              (if route = Home then txt "Home "
               else a [ href "/home" ] [ txt "Home" ]);
              txt " | ";
              (if route = About then txt "About "
               else a [ href "/about" ] [ txt "About" ]);
              txt " | ";
              (if route = News then txt "News "
               else a [ href "/news" ] [ txt "News" ]);
              txt " | ";
              (if route = Software then txt "Software "
               else a [ href "/software" ] [ txt "Software" ]);
              txt " | ";
              (if route = Archive then txt "Archive"
               else a [ href "/archive" ] [ txt "Archive" ]);
            ];
        ];
    ]
end

module Footer = struct
  (** Define the content of the footer. *)

  type t = { copyright : string; contact : string  (** An address mail.*) }

  let filename = "footer.json"
  let default = { copyright = "© 2024 My Project"; contact = "" }

  let footer =
    match Assets.read filename with
    | None -> default
    | Some content ->
        let json = JSON.parse ~origin:filename content in
        let copyright = JSON.(json |-> "copyright" |> as_string) in
        let contact = JSON.(json |-> "contact" |> as_string) in
        { copyright; contact }

  let html =
    let website_footer = footer in
    let open Dream_html in
    let open HTML in
    [
      p []
        [
          txt "%s" website_footer.copyright;
          a
            [ href "mailto:%s" website_footer.contact; style_ "float:right;" ]
            [ txt "%s" website_footer.contact ];
        ];
    ]
end

module Home = struct
  (** Define the home page. *)
  let html =
    let open Dream_html in
    let open HTML in
    [ h2 [] [ txt "News" ] ]
    @ News.html_short
    @ [ h2 [] [ txt "Software" ] ]
    @ Softwares.html
end

let index route =
  let open Dream_html in
  let open HTML in
  let main =
    match route with
    | Home -> main [] Home.html
    | News -> main [] @@ [ h1 [] [ txt "News" ] ] @ News.html
    | Software -> main [] @@ [ h1 [] [ txt "Softwares" ] ] @ Softwares.html
    | Archive -> main [] @@ [ h1 [] [ txt "All posts" ] ] @ News.post_html
    | About -> main [] @@ [ h1 [] [ txt "About" ] ] @ About.html
    | Post { filename } -> (
        main []
        @@
        match Assets.read filename with
        | None -> []
        | Some content -> [ txt ~raw:true "%s" content ])
  in
  respond
    (html
       [ lang "en" ]
       [
         head [] Head.html;
         body []
           [
             header [] (Header.html route);
             (* The main corpus is separated from the header and the footer with a line. *)
             hr [];
             main;
             hr [];
             footer [] Footer.html;
           ];
       ])

(* This function is used to download static assets. Using `ocaml-crunch`, assets
   are read from file loaded into the website binary itself. *)
let loader _root path _request =
  match Assets.read path with
  | None -> Dream.empty `Not_Found
  | Some asset -> Dream.respond asset

let () =
  (* Accept connections from any interface. This is necessary since the website
     aims to be run from a docker container. *)
  Dream.run ~interface:"0.0.0.0"
  @@ Dream.logger
  @@ Dream.router
       [
         Dream.get "/assets/**" (Dream.static ~loader "");
         Dream.get "/content/**" (fun request ->
             let filename = Dream.target request in
             index (Post { filename }));
         Dream.get "/" (fun _ -> index Home);
         Dream.get "/home" (fun _ -> index Home);
         Dream.get "/about" (fun _ -> index About);
         Dream.get "/archive" (fun _ -> index Archive);
         Dream.get "/news" (fun _ -> index News);
         Dream.get "/software" (fun _ -> index Software);
       ]
