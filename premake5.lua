-- Clean by just deleting entire visual_studio directory
if _ACTION == "clean" then
  os.rmdir("../visual_studio")
  os.exit()
end

-- Qt adjustments for premake
include "qt.lua"
local qt = premake.extensions.qt

local dependencies = {}
local projects = {}
local layers = {{}, {}, {}, {}} -- 4 layers total

---------------------------------------------------------------------------
-- Call this to add a new external dependency.
---------------------------------------------------------------------------
-- Name - The name this dependency will be referred to as throughout this
--        premake file. This is what you put into your project.
-- Debug Links - The names of any additional links needed when this
--               dependency is used in a project (Debug mode)
-- Release Links - The names of any additional links needed when this
--                 dependency is used in a project (Release mode).
-- Include directories - The folders in which to find headers for this.
--                       This is relative to "../framework/".
-- Library directories - The folders in which to find the library for this.
--                       This is relative to "../framework/".
-- Runtime Files - Files that need to be in the exe directory when the
--                 executable runs. This is relative to "../framework".
--                 Note that backslashes must be used in this path because
--                 of limitations with visual studio post-build commands.
---------------------------------------------------------------------------
function RegisterDependency(name, debugLinks, releaseLinks, incDirs, libDirs, runtimeFiles)
  dependencies[name] =
    { name = name, debugLinks = debugLinks, releaseLinks = releaseLinks,
      includeDirs = incDirs, libraryDirs = libDirs, runtimeFiles = runtimeFiles }
end

RegisterDependency("Qt",
                  {"Qt5Cored.lib", "Qt5Guid.lib", "Qt5Widgetsd.lib"},
                  {"Qt5Core.lib", "Qt5Gui.lib", "Qt5Widgets.lib"},
                  {"Qt"},
                  {"../Qt/lib/**"})

-------------------------------------
-- Add all other dependencies here --
-------------------------------------

---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Call these to add new projects to the solution.
---------------------------------------------------------------------------
-- Name - The name of this project. Has to match the src directory name.
--
-- Kind - How to compile this project. There are only 4 valid kinds:
--        "StaticLib", "WindowedApp", "ConsoleApp", "SharedLib".
--        RegisterLibrary automatically sets it to "StaticLib"
--
-- Layer - Where this project lies in the compilation order. All projects
--         depend on each layer below them. (All layers are ints)
--         1: First Compiled, Core
--         2: System Libraries
--         3: Systems and components
--         4: Sandboxes and Executables
--         Executables are always in Layer 4
--
-- dependencyNames - (Optional) Names of registered dependencies for this project.
--                   If not specified, defaults to empty list {}.
--
-- flags - (Optional) Any premake flags that should be specified for this project.
--         For a list go here: https://bitbucket.org/premake/premake-dev/wiki/flags
--         If not specified, defaults to empty list {}.
--
-- pchinfo - (Optional) A 2-element table with the precompiled header's header
--           and path relative to your project directory.
--           For example, {"precompiled.h", "precompiled/precompiled.cpp"}
--           will use src/myproject/precompiled/precompiled.cpp as a
--           precompiled header. If not specified, is not included in the table.
---------------------------------------------------------------------------
function RegisterExecutable(name, kind, dependencyNames, flags, pchinfo, language)
  local tempTable = {}

  tempTable.name = name
  tempTable.kind = kind
  tempTable.layer = 4
  tempTable.flags = flags or {}
  tempTable.dependencyNames = dependencyNames or {}
  if type(pchinfo) == "table" and table.maxn(pchinfo) == 2 then
    tempTable.pchinfo = pchinfo
  end
  tempTable.language = language or "C++"

  projects[name] = tempTable
  table.insert(layers[4], name)
end

function RegisterLibrary(name, layer, dependencyNames, flags, pchinfo)
  local tempTable = {}

  tempTable.name = name
  tempTable.kind = "StaticLib"
  tempTable.layer = layer
  tempTable.flags = flags or {}
  tempTable.dependencyNames = dependencyNames or {}
  if type(pchinfo) == "table" and table.maxn(pchinfo) == 2 then
    tempTable.pchinfo = pchinfo
  end

  projects[name] = tempTable
  table.insert(layers[layer], name)
end

--------------------------------------------------
-- Register your executables and libraries here --
--------------------------------------------------
-- Example Executable, Update with engine dependencies
RegisterExecutable("QtEditor", "WindowedApp", {"Qt"}, nil, nil, "Qt")

-- Example Library
RegisterLibrary("EngineLib", 1)

---------------------------------------------------------------------------
-- Functions for creating actual solution.
---------------------------------------------------------------------------
function AddRuntimeCopyCommands(runtimeFiles, runtimeDest)
  if runtimeFiles ~= nil then
    local copyCommands = { }
    for i = 1, #runtimeFiles do
      table.insert(copyCommands,
         "copy \"$(SolutionDir)..\\..\\framework\\" .. runtimeFiles[i]
         .. "\" \"" .. runtimeDest .. "\"")
    end
    postbuildcommands(copyCommands)
  end
end

-------------------------------------------
-- Links the dependencies to the project --
-------------------------------------------
function LinkDependencies(dependencyNames, runtimeDest)
  for i = 1, #dependencyNames do
    local dependency = dependencies[dependencyNames[i]]

    for i = 1, #dependency.includeDirs do
      includedirs("../framework/" .. dependency.includeDirs[i])
    end

    for i = 1, #dependency.libraryDirs do
      libdirs("../framework/" .. dependency.libraryDirs[i])
    end

    -- Extra configurations need to be added here
    configuration "Debug"
      links(dependency.debugLinks)

    configuration "ReleaseSymbols"
      links(dependency.releaseLinks)

    configuration "Release"
      links(dependency.releaseLinks)

    -- Copy runtime files  to the correct destinations
    if runtimeDest ~= nil then
      configuration "Debug"
        AddRuntimeCopyCommands(dependency.runtimeFiles, runtimeDest.."/Debug")
      configuration "ReleaseSymbols"
        AddRuntimeCopyCommands(dependency.runtimeFiles, runtimeDest.."/ReleaseSymbols")
      configuration "Release"
        AddRuntimeCopyCommands(dependency.runtimeFiles, runtimeDest.."/Release")
    end
  end
end

function LinkLowerLayers(layer, runtimeDest)
  for i = 1, layer - 1 do
    local projectnames = layers[i]

    configuration {}
    links(projectnames)

    for key, name in pairs(projectnames) do
      local proj = projects[name]
      LinkDependencies(proj.dependencyNames, runtimeDest)
    end
  end
end

--------------------------------------
-- Adds the project to the solution --
--------------------------------------
function AddProject(proj)
  if proj.kind == "StaticLib" then
    group "Libraries"
  else
    group "Executables"
  end

  project(proj.name)
    kind(proj.kind)
    location("../visual_studio/Projects/Application/" .. proj.name)
    targetname(proj.name)

    -------------------------------------
    -- Special section for Qt projects --
    -------------------------------------
    if proj.language == "Qt" then
      language("C++")
      qt.enable()
      qtpath "../Qt"

      -- Update this for any other Qt modules you will be using
      qtmodules{ "core", "gui", "widgets" }
      qtprefix "Qt5"
      configuration { "Debug" }
        qtsuffix "d"
      configuration {}
    else
      language(proj.language)
    end

    ----------------------------------------------------------
    -- Add all filetypes that will be used in your projects --
    ----------------------------------------------------------
    files 
    {
      "../src/" .. proj.name .. "/**.cpp",
      "../src/" .. proj.name .. "/**.h",
      "../src/" .. proj.name .. "/**.hpp",
      "../src/" .. proj.name .. "/**.ui",
      "../src/" .. proj.name .. "/**.qrc",
    }

    objdir("../visual_studio/build/" .. proj.name)
    flags(proj.flags)

    ------------------------------------
    -- Precompiled Header Information --
    ------------------------------------
    if type(proj.pchinfo) == "table" then
      pchheader(proj.pchinfo[1])
      pchsource("../src/" .. proj.name .. "/" .. proj.pchinfo[2])
    elseif proj.language == "Qt" or proj.language == "C++" then
      files { "../src/stdinc.h", "../src/stdinc.cpp" }
      pchheader "stdinc.h"
      pchsource "../src/stdinc.cpp"
    end

    -------------------------
    -- Runtime destination --
    -------------------------
    local subdir
    local runtimeDest
    if proj.kind == "StaticLib" then
      subdir = "libs/"
      runtimeDest = nil
    else
      subdir = "bin/"
      runtimeDest = "$(SolutionDir)..\\bin\\"..proj.name
    end

    ----------------------------------------
    -- Add all libraries and dependencies --
    ----------------------------------------
    if proj.kind == "StaticLib" then
      includedirs 
      {
        "../framework",
        "../src",
        "../src/**",
        "../framework/**",
      }
    elseif proj.language == "Qt" or proj.language == "C++" then
      libdirs 
      {
        "../framework/**",
      }
      LinkLowerLayers(proj.layer, runtimeDest)
      LinkDependencies(proj.dependencyNames, runtimeDest)
    end

    --------------------------------------
    -- Target Directory For Build Files --
    --------------------------------------
    configuration "Debug"
      targetdir("../visual_studio/" .. subdir .. proj.name .. "/Debug")

    configuration "ReleaseSymbols"
      targetdir("../visual_studio/" .. subdir .. proj.name .. "/ReleaseSymbols")

    configuration "Release"
      targetdir("../visual_studio/" .. subdir .. proj.name .. "/Release")
end

function AddProjects()
  for name, project in pairs(projects) do
    AddProject(project)
  end
end


---------------------------------------------------------------------------
-- Solution
---------------------------------------------------------------------------
-- Create the actual solution here
---------------------------------------------------------------------------
solution "QtEditor"
  configurations {"Debug", "Release", "ReleaseSymbols"}
  location "../visual_studio/Solution"
  language "C++"

  -- Only needed if you have multiple executables in your project
  startproject "QtEditor"

  -- Directory with include files
  includedirs 
  {
    "../src",
    "../src/**",
    "../framework",
    "../framework/**"
  }

  -- Executable will be run from this folder
  debugdir "../Resources/"

  links {  }

  vpaths { ["*"] = "src" }

  -- Add any other solution flags
  flags { "FatalWarnings", "MultiProcessorCompile" }

  -- Add any solution defines (We use the _EDITOR for our project)
  defines { "_EDITOR", "_CRT_SECURE_NO_WARNINGS" }

  -- Set linkoptions for ReleaseSymbols versions of executables
  configuration {"WindowedApp or ConsoleApp", "ReleaseSymbols"}
    linkoptions {"/OPT:REF", "/OPT:ICF", "/ignore:4099"}

  -- Debug has no optimizations
  configuration "Debug"
    flags { "Symbols" }
    defines {"DEBUG", "DEBUGLOGGING", "HOT_LOADING" }
    optimize "Debug"
    linkoptions {"/NODEFAULTLIB:msvcrt.lib", "/ignore:4099"}

  -- Release w/ Symbols has optimizations but still allows symbolic debug
  configuration "ReleaseSymbols"
    flags { "Symbols", "NoIncrementalLink" }
    defines { "RELEASE", "DEBUGLOGGING", "AK_OPTIMIZED", "HOT_LOADING"}
    optimize "Speed"
    linkoptions {"/ignore:4099"}

  -- Typical Release mode (You shouldn't be using this)
  configuration "Release"
    flags { "NoIncrementalLink" }
    defines { "RELEASE", "AK_OPTIMIZED" }
    optimize "Speed"
    linkoptions {"/ignore:4099"}

  AddProjects()
