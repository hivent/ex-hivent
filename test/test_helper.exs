{:ok, _} = Application.ensure_all_started(:hivent)
{:ok, _} = Application.ensure_all_started(:test_server)
ExUnit.start()
