{
  description = "A simple flake with 1 template";

  outputs = { self }: {

    templates = {

      default = {
        path = ./default;
        description = "Basic NixOS config flake";
      };

    };

    defaultTemplate = self.templates.default;

  };
}