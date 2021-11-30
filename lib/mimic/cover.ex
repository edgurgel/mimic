defmodule Mimic.Cover do
  @moduledoc """
  Abuse cover private functions to move stuff around.

  Completely based on meck's solution:
  https://github.com/eproxus/meck/blob/2c7ba603416e95401500d7e116c5a829cb558665/src/meck_cover.erl#L67-L91
  """

  @doc false
  def export_private_functions do
    {_, binary, _} = :code.get_object_code(:cover)
    {:ok, {_, [{_, {_, abstract_code}}]}} = :beam_lib.chunks(binary, [:abstract_code])
    {:ok, module, binary} = :compile.forms(abstract_code, [:export_all])
    :code.load_binary(module, '', binary)
  end

  @doc false
  def replace_cover_data!(module, original_filename, original_cover_data) do
    original_module = Mimic.Module.original(module)

    case export_cover_data!(original_module) do
      {:ok, path} ->
        rewrite_cover_data!(path, module)
        Mimic.Module.clear!(original_module)
        :cover.compile_beam(original_filename)
        :ok = :cover.import(path)
        File.rm(path)

      _ ->
        :ok
    end

    Mimic.Module.clear!(module)

    :ok = :cover.import(original_cover_data)
    File.rm(original_cover_data)
  end

  @doc false
  def export_cover_data!(module) do
    path = Path.expand("#{module}-#{:os.getpid()}.coverdata", ".")

    case :cover.export(path, module) do
      :ok ->
        {:ok, path}

      error ->
        File.rm(path)
        error
    end
  end

  defp rewrite_cover_data!(path, module) do
    terms = get_terms(path)
    terms = replace_module_name(terms, module)
    write_cover_data!(path, terms)
  end

  defp replace_module_name(terms, module) do
    Enum.map(terms, fn term -> do_replace_module_name(term, module) end)
  end

  defp do_replace_module_name({:file, old, file}, module) do
    {:file, module, String.replace(file, to_string(old), to_string(module))}
  end

  defp do_replace_module_name({bump = {:bump, _mod, _, _, _, _}, value}, module) do
    {put_elem(bump, 1, module), value}
  end

  defp do_replace_module_name({_mod, clauses}, module) do
    {module, replace_module_name(clauses, module)}
  end

  defp do_replace_module_name(clause = {_mod, _, _, _, _}, module) do
    put_elem(clause, 0, module)
  end

  defp get_terms(path) do
    {:ok, resource} = File.open(path, [:binary, :read, :raw])
    terms = get_terms(resource, [])
    File.close(resource)
    terms
  end

  defp get_terms(resource, terms) do
    case apply(:cover, :get_term, [resource]) do
      :eof -> terms
      term -> get_terms(resource, [term | terms])
    end
  end

  defp write_cover_data!(path, terms) do
    {:ok, resource} = File.open(path, [:write, :binary, :raw])
    Enum.each(terms, fn term -> apply(:cover, :write, [term, resource]) end)
    File.close(resource)
  end
end
