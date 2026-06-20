{ lib }:
{
  config,
  compiledProfiles ? {
    tasks = { };
  },
}:
let
  allTasks = compiledProfiles.tasks // config.devcontainer.lifecycle.tasks;
  taskNames = lib.sort lib.lessThan (builtins.attrNames allTasks);
  tasks = map (
    name:
    let
      task = allTasks.${name};
    in
    task // { inherit name; }
  ) taskNames;
  phases = lib.unique (map (task: task.phase) tasks);
in
{
  tasks = tasks;
  phases = phases;
}
