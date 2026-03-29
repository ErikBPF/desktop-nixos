_: {
  flake.modules.nixos.dev-python = {pkgs, ...}: {
    environment.systemPackages = with pkgs; [
      (python3.withPackages (ps:
        with ps; [
          pip
          setuptools
          wheel
          virtualenv
          pip-tools
          pipenv
          pytest
          pytest-cov
          black
          isort
          flake8
          mypy
          pylint
          autopep8
          bandit
          safety
          pre-commit
          jupyter
          ipython
          notebook
          jupyterlab
          pandas
          numpy
          matplotlib
          requests
          flask
          django
          fastapi
          uvicorn
          celery
          redis
          psycopg2
          sqlalchemy
          alembic
          pydantic
          click
          rich
          typer
          pydocstyle
          sphinx
          mkdocs
        ]))
      uv
      pyright
      ruff
    ];

    systemd.user.services."uv-tool-specify-cli" = {
      description = "Install specify-cli uv tool";
      wantedBy = ["default.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = toString (pkgs.writeShellScript "uv-install-specify-cli" ''
          ${pkgs.uv}/bin/uv tool install specify-cli \
            --from git+https://github.com/github/spec-kit.git
        '');
      };
    };

    environment.sessionVariables = {
      PYTHONPATH = "$HOME/.local/lib/python3.12/site-packages:$PYTHONPATH";
      PYTHONSTARTUP = "$HOME/.pythonrc";
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
      PYTHONIOENCODING = "utf-8";
      VIRTUAL_ENV_DISABLE_PROMPT = "1";
      PIP_REQUIRE_VIRTUALENV = "false";
      PIP_DISABLE_PIP_VERSION_CHECK = "1";
      PIP_NO_CACHE_DIR = "1";
      PYTHONBREAKPOINT = "pdb.set_trace";
      PYTHONWARNINGS = "default";
    };
  };
}
