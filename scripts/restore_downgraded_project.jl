#!/usr/bin/env julia

using TOML

function restored_manifest_entry(project::AbstractDict, path::AbstractString)
    entry = Dict{String, Any}(
        "path" => path,
        "uuid" => project["uuid"],
    )
    hard_deps = sort!(collect(keys(get(project, "deps", Dict{String, Any}()))))
    isempty(hard_deps) || (entry["deps"] = hard_deps)
    for key in ("weakdeps", "extensions")
        values = get(project, key, nothing)
        values isa AbstractDict && !isempty(values) && (entry[key] = deepcopy(values))
    end
    haskey(project, "version") && (entry["version"] = project["version"])
    return entry
end

function local_manifest_entry(entries, manifest_dir::AbstractString, project_dir::AbstractString)
    matches = findall(entries) do entry
        path = get(entry, "path", nothing)
        path isa AbstractString || return false
        return realpath(abspath(manifest_dir, path)) == realpath(project_dir)
    end
    length(matches) == 1 || error(
        "expected exactly one local manifest entry for $project_dir, found $(length(matches))",
    )
    return only(matches)
end

"""
    restore_downgraded_project(project_dir)

Repair the local package entry in a downgrade-generated `Manifest.toml` after
restoring the package's original `Project.toml`. Resolved package versions and
test-only manifest entries are retained.
"""
function restore_downgraded_project(project_dir::AbstractString)
    project_dir = normpath(abspath(project_dir))
    project_path = joinpath(project_dir, "Project.toml")
    manifest_path = joinpath(project_dir, "Manifest.toml")
    project = TOML.parsefile(project_path)
    manifest = TOML.parsefile(manifest_path)

    package_name = project["name"]
    entries = manifest["deps"][package_name]
    entry_index = local_manifest_entry(entries, dirname(manifest_path), project_dir)
    existing_path = entries[entry_index]["path"]
    entries[entry_index] = restored_manifest_entry(project, existing_path)
    pop!(manifest, "project_hash", nothing)

    temporary_path, io = mktemp(dirname(manifest_path))
    try
        TOML.print(io, manifest; sorted = true)
        close(io)
        mv(temporary_path, manifest_path; force = true)
    catch
        close(io)
        rm(temporary_path; force = true)
        rethrow()
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 1 || error("usage: restore_downgraded_project.jl PROJECT_DIR")
    restore_downgraded_project(only(ARGS))
end
