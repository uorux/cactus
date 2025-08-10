{
  description = "Astro Cactus site with Docker image";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        nodejs = pkgs.nodejs_22;

        # Build the Astro site
        astroSite = pkgs.stdenv.mkDerivation rec {
          pname = "astro-cactus";
          version = "6.7.0";

          src = ./.;

          nativeBuildInputs = with pkgs; [
            nodejs
            pnpm_9.configHook
          ];

          pnpmDeps = pkgs.pnpm_9.fetchDeps {
            inherit pname version src;
            fetcherVersion = 2;
            hash = "sha256-ZCxJfsMCPhl4oh4iNuc0BQwEffUEbKp4IR5WS/AiGbI=";
          };

          buildPhase = ''
            runHook preBuild

            pnpm build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp -r dist/* $out/

            runHook postInstall
          '';
        };

        # Nginx configuration
        nginxConfig = ./nginx.conf;

        # Docker image with Nginx
        dockerImage = pkgs.dockerTools.buildImage {
          name = "astro-cactus";
          tag = "latest";

          contents = with pkgs; [
            # Nginx and dependencies
            nginx
          ];

          runAsRoot = ''
            #!${pkgs.runtimeShell}
            # Create necessary directories
            mkdir -p /var/www/html
            mkdir -p /var/log/nginx
            mkdir -p /var/cache/nginx
            mkdir -p /etc/nginx
            mkdir -p /tmp

            # Copy Astro build output
            cp -r ${astroSite}/* /var/www/html/

            # Copy nginx config and mime.types
            cp ${nginxConfig} /etc/nginx/nginx.conf
            cp ${pkgs.nginx}/conf/mime.types /etc/nginx/mime.types

            # Create nginx user and group, and nobody user
            echo "nginx:x:101:101:nginx:/var/cache/nginx:/bin/false" >> /etc/passwd
            echo "nginx:x:101:" >> /etc/group
            echo "nobody:x:65534:65534:nobody:/nonexistent:/bin/false" >> /etc/passwd
            echo "nogroup:x:65534:" >> /etc/group

            # Set permissions
            chmod -R 755 /var/www/html
            chmod -R 755 /var/log/nginx
            chmod -R 755 /var/cache/nginx
            chmod -R 755 /tmp
          '';

          config = {
            Cmd = [
              "${pkgs.nginx}/bin/nginx"
              "-g"
              "daemon off;"
              "-c"
              "/etc/nginx/nginx.conf"
            ];
            ExposedPorts = {
              "80/tcp" = { };
            };
            WorkingDir = "/";
          };
        };

      in
      {
        packages = {
          default = astroSite;
          site = astroSite;
          dockerImage = dockerImage;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nodejs
            pnpm_9
          ];
        };
      }
    );
}
