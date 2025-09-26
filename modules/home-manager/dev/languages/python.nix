{
  pkgs,
  ...
}: {
  # Python packages
  home.packages = with pkgs; [
    # Python language and tools
    python312
    python312Packages.pip
    python312Packages.setuptools
    python312Packages.wheel
    python312Packages.virtualenv
    python312Packages.pip-tools
    python312Packages.pipenv
    python312Packages.poetry
    python312Packages.pytest
    python312Packages.pytest-cov
    python312Packages.black
    python312Packages.isort
    python312Packages.flake8
    python312Packages.mypy
    python312Packages.pylint
    python312Packages.autopep8
    python312Packages.bandit
    python312Packages.safety
    python312Packages.pre-commit
    python312Packages.jupyter
    python312Packages.ipython
    python312Packages.notebook
    python312Packages.jupyterlab
    python312Packages.pandas
    python312Packages.numpy
    python312Packages.matplotlib
    python312Packages.requests
    python312Packages.flask
    python312Packages.django
    python312Packages.fastapi
    python312Packages.uvicorn
    python312Packages.celery
    python312Packages.redis
    python312Packages.psycopg2
    python312Packages.sqlalchemy
    python312Packages.alembic
    python312Packages.pydantic
    python312Packages.click
    python312Packages.rich
    python312Packages.typer
    python312Packages.pydocstyle
    python312Packages.sphinx
    python312Packages.mkdocs
    
    # Additional Python tools
    uv # Fast Python package installer
    pyright # Python language server
    python-lsp-server # Python LSP server
    jedi-language-server # Jedi-based LSP server
    ruff # Fast Python linter and formatter
    pyflakes # Python linter
    pycodestyle # Python style checker
    pydocstyle # Python docstring checker
  ];

  # Environment variables for Python
  home.sessionVariables = {
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
    
    # Path configuration
    PATH = "$PATH:$HOME/.local/bin";
  };
}
