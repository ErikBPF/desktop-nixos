{pkgs, ...}: {
  # Python packages
  environment.systemPackages = with pkgs; [
    # Python with essential packages
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

    # Additional Python tools
    uv # Fast Python package installer
    pyright # Python language server
    ruff # Fast Python linter and formatter
  ];

  # Environment variables for Python
  environment.sessionVariables = {
    # Python settings
    PYTHONPATH = "$HOME/.local/lib/python3.12/site-packages:$PYTHONPATH";
    PYTHONSTARTUP = "$HOME/.pythonrc";
    PYTHONDONTWRITEBYTECODE = "1";
    PYTHONUNBUFFERED = "1";
    PYTHONIOENCODING = "utf-8";

    # Virtual environment settings
    VIRTUAL_ENV_DISABLE_PROMPT = "1";
    PIP_REQUIRE_VIRTUALENV = "false";
    PIP_DISABLE_PIP_VERSION_CHECK = "1";
    PIP_NO_CACHE_DIR = "1";

    # Development settings
    PYTHONBREAKPOINT = "pdb.set_trace";
    PYTHONWARNINGS = "default";
  };
}
