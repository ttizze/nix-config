from python_project import greeting


def test_greeting_uses_the_supplied_name() -> None:
    assert greeting("Nix") == "Hello, Nix!"
