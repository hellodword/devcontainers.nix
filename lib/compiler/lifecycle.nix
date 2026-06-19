{ lib }:
{ config }:
let
  taskNames = lib.sort lib.lessThan (builtins.attrNames config.devcontainer.lifecycle.tasks);
  tasks = map (
    name:
    let
      task = config.devcontainer.lifecycle.tasks.${name};
    in
    task // { inherit name; }
  ) taskNames;
  phases = lib.unique (map (task: task.phase) tasks);
in
{
  tasks = tasks;
  phases = phases;
}
