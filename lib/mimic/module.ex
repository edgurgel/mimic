defmodule Mimic.Module do
  @moduledoc false

  def original(module), do: "#{module}.Mimic.Original.Module" |> String.to_atom()

  def clear!(module) do
    :code.purge(module)
    :code.delete(module)
    {:module, ^module} = :code.ensure_loaded(module)
    :ok
  end

  def replace!(module, backup_module) do
    rename_module(module, backup_module)
    Code.compiler_options(ignore_module_conflict: true)
    create_mock(module)
    Code.compiler_options(ignore_module_conflict: false)

    :ok
  end

  defp rename_module(module, new_module) do
    beam_file =
      case :code.get_object_code(module) do
        {_, binary, _filename} -> binary
        _error -> throw({:object_code_not_found, module})
      end

    result =
      case :beam_lib.chunks(beam_file, [:abstract_code]) do
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} -> forms
        {:ok, {_, [{:abstract_code, :no_abstract_code}]}} -> throw(:no_abstract_code)
      end
      |> rename_attribute(new_module)

    case :compile.forms(result, [:return_errors]) do
      {:ok, module_name, binary} ->
        load_binary(module_name, binary)
        binary

      {:ok, module_name, binary, _Warnings} ->
        load_binary(module_name, binary)
        Binary

      error ->
        exit({:compile_forms, error})
    end
  end

  defp load_binary(module, binary) do
    case :code.load_binary(module, '', binary) do
      {:module, ^module} -> :ok
      {:error, reason} -> exit({:error_loading_module, module, reason})
      _ -> :yolo
    end
  end

  defp rename_attribute([{:attribute, line, :module, {_, vars}} | t], new_name) do
    [{:attribute, line, :module, {new_name, vars}} | t]
  end

  defp rename_attribute([{:attribute, line, :module, _} | t], new_name) do
    [{:attribute, line, :module, new_name} | t]
  end

  defp rename_attribute([h | t], new_name), do: [h | rename_attribute(t, new_name)]

  defp create_mock(module) do
    mimic_info = module_mimic_info()
    mimic_functions = generate_mimic_functions(module)
    Module.create(module, [mimic_info | mimic_functions], Macro.Env.location(__ENV__))
    module
  end

  defp module_mimic_info() do
    quote do: def(__mimic_info__, do: :ok)
  end

  defp generate_mimic_functions(module) do
    internal_functions = [__info__: 1, module_info: 0, module_info: 1]

    for {fn_name, arity} <- module.module_info(:exports),
        {fn_name, arity} not in internal_functions do
      args = 0..arity |> Enum.to_list() |> tl() |> Enum.map(&Macro.var(:"arg_#{&1}", Elixir))

      quote do
        def unquote(fn_name)(unquote_splicing(args)) do
          Mimic.Server.apply(__MODULE__, unquote(fn_name), unquote(args))
        end
      end
    end
  end
end
