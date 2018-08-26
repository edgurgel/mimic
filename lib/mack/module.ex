defmodule Mack.Module do
  @moduledoc """
  Module to handle module generation and reconstruction
  """

  @doc """
  Remove proxy module reloading original `module`
  """
  @spec clear!(module) :: :ok
  def clear!(module) do
    :code.purge(module)
    :code.delete(module)
    {:module, ^module} = :code.ensure_loaded(module)
    :ok
  end

  @doc """
  Replace `module` with a `Mack.Proxy` keeping the original module as
  `backup_module`
  """
  @spec replace!(module, module) :: :ok
  def replace!(module, backup_module) do
    contents =
      quote do
        use Mack.Server
      end

    rename_module(module, backup_module)
    Code.compiler_options(ignore_module_conflict: true)
    Module.create(module, contents, Macro.Env.location(__ENV__))
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
end
