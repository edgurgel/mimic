defmodule Mimic.CompilerOptionsTest do
  use ExUnit.Case, async: false

  @resource {:elixir_compiler_option, :ignore_module_conflict}

  setup do
    previous = Code.get_compiler_option(:ignore_module_conflict)

    on_exit(fn ->
      Code.put_compiler_option(:ignore_module_conflict, previous)
      Mimic.Module.clear!(CompilerOptionTarget)
      {:module, CompilerOptionTarget} = :code.load_file(CompilerOptionTarget)
    end)

    :ok
  end

  for initial <- [false, true] do
    test "successful replacement restores #{initial}" do
      Code.put_compiler_option(:ignore_module_conflict, unquote(initial))
      Mimic.Module.replace!(CompilerOptionTarget, [])
      assert Mimic.Module.copied?(CompilerOptionTarget)
      assert Code.get_compiler_option(:ignore_module_conflict) == unquote(initial)
      assert_lock_released()
    end

    for failure <- [:raise, :throw, :exit] do
      test "#{failure} restores #{initial} and releases the shared lock" do
        Code.put_compiler_option(:ignore_module_conflict, unquote(initial))
        Process.put({CompilerOptionTarget, :action}, unquote(failure))

        case unquote(failure) do
          :raise ->
            assert_raise RuntimeError, "replacement failed", fn ->
              Mimic.Module.replace!(CompilerOptionTarget, [])
            end

          :throw ->
            assert catch_throw(Mimic.Module.replace!(CompilerOptionTarget, [])) ==
                     :replacement_failed

          :exit ->
            assert catch_exit(Mimic.Module.replace!(CompilerOptionTarget, [])) ==
                     :replacement_failed
        end

        assert Code.get_compiler_option(:ignore_module_conflict) == unquote(initial)
        assert_lock_released()
      end
    end
  end

  test "a cooperating generator cannot acquire the lock during replacement" do
    parent = self()

    task =
      Task.async(fn ->
        Process.put({CompilerOptionTarget, :action}, {:barrier, parent})
        Mimic.Module.replace!(CompilerOptionTarget, [])
      end)

    assert_receive {:inside_replacement, pid}, 5_000
    assert Code.get_compiler_option(:ignore_module_conflict)
    refute :global.set_lock({@resource, self()}, [node()], 0)
    send(pid, :continue)
    Task.await(task)
    assert Mimic.Module.copied?(CompilerOptionTarget)
    assert_lock_released()
  end

  defp assert_lock_released do
    probe =
      Task.async(fn ->
        acquired = :global.set_lock({@resource, self()}, [node()], 0)
        if acquired, do: :global.del_lock({@resource, self()}, [node()])
        acquired
      end)

    assert Task.await(probe)
  end
end
