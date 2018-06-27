Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.IO;

namespace dwb {
    public class Workbench {
        public static Workbench Open(string path) {
            return new Workbench(path);
        }

        public Workbench(string path) {
            if (String.IsNullOrEmpty(path)) {
                throw new ArgumentException("Path not found: " + path, "path");
            }
            if (!Directory.Exists(path)) {
                throw new DirectoryNotFoundException(path);
            }
            var resolvedPath = System.IO.Path.GetFullPath(path);
            if (!resolvedPath.ToLower().Equals(path.ToLower())) {
                throw new ArgumentException("Absolute path required");
            }

            this._path = resolvedPath;
            this.ObjRoot = System.IO.Path.Combine(resolvedPath, "obj");
            this.BinRoot = System.IO.Path.Combine(resolvedPath, "bin");
            this.ExtRoot = System.IO.Path.Combine(resolvedPath, "ext");

            var maybeFile = System.IO.Path.Combine(resolvedPath, "dwb.projects.xml");
            if (File.Exists(maybeFile)) { DefinitionFile = maybeFile; }

            if (!Directory.Exists(ObjRoot)) { Directory.CreateDirectory(ObjRoot); }
            if (!Directory.Exists(BinRoot)) { Directory.CreateDirectory(BinRoot); }
            if (!Directory.Exists(ExtRoot)) { Directory.CreateDirectory(ExtRoot); }

            var extlib = System.IO.Path.Combine(ExtRoot, "lib");
            if (!Directory.Exists(extlib)) { Directory.CreateDirectory(extlib); }
        }

        public string Path { get { return _path; } }
        public string BinRoot { get; set; }
        public string ObjRoot { get; set; }
        public string ExtRoot { get; set; }
        public string DefinitionFile { get; private set; }

        public override string ToString() { return (new DirectoryInfo(_path)).Name; }

        private string _path;
    }

    public enum BuildPlatform {
        x86,
        x64
    }

    public enum BuildConfiguration {
        Debug,
        Release
    }

    public class BuildContext {
        public Workbench Workbench { get; set; }
        public BuildPlatform Platform { get; set; }
        public BuildConfiguration Configuration { get; set; }
        public List<Project> Projects { get { return _projects; } }

        private List<Project> _projects = new List<Project>();

        public string GetProjectBuildTree(Project p) {
            return System.IO.Path.Combine(
                System.IO.Path.Combine(
                    System.IO.Path.Combine(this.Workbench.ObjRoot, this.Configuration.ToString()), this.Platform.ToString()), p.Name);
        }

        public static BuildContext CurrentContext;
    }

    public class Project {
        public string Name { get; set; }
        public string Path { get; set; }
        public Dictionary<string,string> Options { get { return _options; } }
        public bool Enabled { get; set; }

        private Dictionary<string,string> _options = new Dictionary<string,string>();
    }
}
"@

Function _New-Project($name, $path) {
    $p = New-Object dwb.Project;
    $p.Name = $name;
    $p.Path = $path;
    $p.Enabled = $true;
    return $p;
}

Function _Load-ProjectSpec($filename) {
    $xml = [xml](gc $filename);
    $rootdir = Split-Path $filename -Parent;
    $xml.SelectNodes("//project") | %{
        $p = _New-Project $_.Name (Join-Path $rootdir $_.Path)
        $_.SelectNodes("option") | %{
            $p.Options[$_.Name] = $_.Value;
        }
        $p;
    }
}

Function Enter-Workbench{
    Param(
        [string]$Path,
        [dwb.BuildPlatform]$Platform = "x64",
        [dwb.BuildConfiguration]$Configuration = "Debug"
    )
    Process {
        if (!$Path) {
            $Path = pwd;
        }
        $Path = Resolve-Path $Path;
        $wb = [dwb.Workbench]::Open($Path);
        [dwb.BuildContext]::CurrentContext = New-Object dwb.BuildContext;
        [dwb.BuildContext]::CurrentContext.Workbench = $wb;
        [dwb.BuildContext]::CurrentContext.Platform = $Platform;
        [dwb.BuildContext]::CurrentContext.Configuration = $Configuration;

        $pname = [IO.Path]::GetFileName($Path);

        if ($wb.DefinitionFile) {
            _Load-ProjectSpec $wb.DefinitionFile | %{ [dwb.BuildContext]::CurrentContext.Projects.Add($_); }
        } elseif (Test-Path "$Path\CMakeLists.txt") {
            [dwb.BuildContext]::CurrentContext.Projects.Add((_New-Project $pname $Path));
        } elseif (Test-Path "$Path\src\CMakeLists.txt") {
            [dwb.BuildContext]::CurrentContext.Projects.Add((_New-Project $pname "$Path\src"));
        }
    }
}

Function Reload-Workbench {
    $ctx = [dwb.BuildContext]::CurrentContext;
    $ctx.Projects.Clear();
    if ($ctx.Workbench.DefinitionFile) {
        _Load-ProjectSpec $ctx.Workbench.DefinitionFile | %{ [dwb.BuildContext]::CurrentContext.Projects.Add($_); }
    }
}

Function Exit-Workbench {
    [dwb.BuildContext]::CurrentContext = $null;
}

Function Get-Workbench {
    Param()
    Process {
        return [dwb.BuildContext]::CurrentContext.Workbench;
    }
}

Function Get-BuildContext {
    Param()
    Process {
        return [dwb.BuildContext]::CurrentContext;
    }
}

Function Focus-Project {
    [CmdletBinding(DefaultParameterSetName="ByAll")]
    Param(
        [Parameter(ParameterSetName="ByName",Position=0)]
        [string[]]$Projects,
        [Parameter(ParameterSetName="ByAll")]
        [switch]$All
    )
    Process {
        if ($Projects) {
            $ctx = [dwb.BuildContext]::CurrentContext;
            $ctx.Projects | %{ $_.Enabled = ($projects -contains $_.Name); }
        } else {
            # All
            $ctx = [dwb.BuildContext]::CurrentContext;
            $ctx.Projects | %{ $_.Enabled = $true; }
        }
    }
}

Function _Populate-ExtTree ($spec, $Sources, $src, $dest) {
    foreach ($Source in $Sources) {
        if (!(Test-Path $Source)) { throw "Unable to access Source $Source"; }
    }
    if (Test-Path $dest) {
        if (!(Test-Path "$dest.ingested")) { throw "Target exists but is not an ingested tree: $dest"; }
        if (!(Test-Path $spec)) { throw "Target txt file does not exist: $spec"; }
    }

    gc $spec | %{
        $f = $_;
        [void](mkdir (Split-Path $dest\$f) -ea 0);
        if (!(Test-Path $dest\$f)) {
            $found = $false;
            foreach ($Source in $Sources) {
                if ((Test-Path $Source\$src\$f) -and !$found) {
                    $found = $true;
                    Write-Verbose "Copying $Source\$src\$f $dest\$f";
                    copy $Source\$src\$f $dest\$f;
                }
            }
            if (!$found) { Write-Warning "Not found: $Target\$f"; }
        }
    }
    echo $Source >"$dest.ingested"
}

Function _Locate-ExtTree($src, $sentinel, $hints) {
    if (Test-Path (Join-Path $src $sentinel)) {
        return $src;

    } else {
        foreach ($hint in $hints) {
            if (Test-Path (Join-Path (Join-Path $src $hint) $sentinel)) {
                return (Join-Path $src $hint);
                break;
            }
        }
    }
}

Function _Populate-ExternalDependencies {
    $wb = [dwb.BuildContext]::CurrentContext.Workbench;
    if ($wb.DefinitionFile) {
        $spec = [xml](gc $wb.DefinitionFile);
        $spec.SelectNodes("/dwb-workbench/dependencies/external") | %{
            $sentinel = $_.sources.locate.file;
            $id = $_.id;
            Write-Verbose "Populate: Looking for $id via $sentinel";

            $src = $null;
            $savedsources = [xml]("<sources />");
            $sourcesfile = Join-Path $wb.Path "dwb.sources.xml";
            Write-Verbose "Populate: Looking for $id in $sourcesfile";
            if (Test-Path $sourcesfile) {
                $savedsources = [xml](gc $sourcesfile);
                $savedsources.SelectNodes("//source[@id='$id']") | %{
                    Write-Verbose "Populate: Looking for $id in $($_.Path)";
                    if (Test-Path $_.Path) {
                        $src = $_.Path;
                    }
                }
            }
            if (!$src) {
                # Accept input
                $src = Read-Host ("Path to {0}" -f $_.description);
                $src = Resolve-Path $src;

                # Save for next time
                $newnode = $savedsources.CreateElement("source");
                $newnode.SetAttribute("id", $id);
                $newnode.SetAttribute("path", $src);
                [void]($savedsources.SelectSingleNode("/sources").AppendChild($newnode));
                $savedsources.Save($sourcesfile);
            }

            $sources = @();
            # Locate sources
            $_.SelectNodes("sources/source") | %{
                $foundroot = _Locate-ExtTree $src $sentinel ($_.SelectNodes("hint") | %{ $_.InnerText })
                Write-Verbose "Found $sentinel in: $foundroot";
                if (!$foundroot) {
                    throw "Unable to find $sentinel";
                }
                $sources += $foundroot;
            }

            # Populate items
            Write-Verbose "Populate: Found $($_.id) in $sources";
            $_.SelectNodes("copy/filelist") | %{
                _Populate-ExtTree (Join-Path $wb.Path $_.spec) $Sources $_.src (Join-Path $wb.Path $_.dest);
            }
        }
    }
}

Function _Run-Command($mydir, $exe, $bargs) {
    Write-Verbose "Command: ($dir) $exe $bargs";
    $p = New-Object System.Diagnostics.Process;
    $p.StartInfo.Filename = "cmake.exe";
    $p.StartInfo.Arguments = $bargs;
    $p.StartInfo.UseShellExecute = $False;
    $p.StartInfo.WorkingDirectory = $mydir;
    [void]($p.Start());
    $p.WaitForExit();

    Write-Verbose "Command: $exe exited with $($p.ExitCode)";
    if ($p.ExitCode) {
        throw "$exe exited with $($p.ExitCode)";
    }
}

Function _Run-CmakeGenerateCommand ($btree, $srctree, $generator, $bargs) {
    $cmd = "`"$srctree`" -G `"$generator`" $bargs"
    _Run-Command $btree "cmake.exe" $cmd;
}

Function _Generate-Project ([dwb.Project]$Project, [dwb.BuildContext]$BuildContext, [bool]$Force) {
    $src = $BuildContext.Workbench.Path;
    $ext = $BuildContext.Workbench.ExtRoot;
    $obj = $BuildContext.GetProjectBuildTree($Project);
    $bin = "$($BuildContext.Workbench.BinRoot)\$($BuildContext.Platform)";

    if ((Test-Path $obj) -and $Force) {
        [void](rmdir -Recurse $obj);
    }
    if (!(Test-Path $obj)) {
        [void](mkdir $obj);
    }
    if (!(Test-Path $bin)) {
        [void](mkdir $bin);
    }

    if ($BuildContext.Platform -eq "x86") {
        $generator = "Visual Studio 15 2017"
    } else {
        $generator = "Visual Studio 15 2017 Win64"
    }

    $options = @{
        "CMAKE_MODULE_PATH" = (@(
            "$src\build",
            $ext
        ) -join ';').Replace("\","/");
        "CMAKE_FRAMEWORK_PATH" = (@(
            $ext,
            "$ext\lib"
        ) -join ';').Replace("\","/");
        "CMAKE_RUNTIME_OUTPUT_DIRECTORY" = $bin;
        "CMAKE_PDB_OUTPUT_DIRECTORY" = $bin;
        "EXT_ROOT" = "$ext\lib";
        "PROJECT_ROOT" = $src;
    };
    if (!($options["CMAKE_TOOLCHAIN_FILE"]) -and $Env:VCPKG_PATH) {
        $vcpkg_toolchain = "$Env:VCPKG_PATH\scripts\buildsystems\vcpkg.cmake";
        if (Test-Path $vcpkg_toolchain) {
            $options["CMAKE_TOOLCHAIN_FILE"] = $vcpkg_toolchain;
        }
    }
    $Project.Options.Keys | %{ $options[$_] = $Project.Options[$_]; }

    $bargs = (($options.Keys | %{ "-D{0}={1}" -f $_, $options[$_] }) -join " ").Replace("\","/");

    _Run-CmakeGenerateCommand $obj $Project.Path $generator $bargs
}

Function _Should-GenerateProject([dwb.Project]$Project, [dwb.BuildContext]$BuildContext){
    Write-Verbose "Should-GenerateProject? $($Project.Name) in $($BuildContext.Workbench.Path)";
    return $true;
#    $obj = $BuildContext.GetProjectBuildTree($Project);
#    if (!((Test-Path $obj) -and (dir $obj).Count -gt 0)) {
#        return $true;
#    } else {
#        return $false;
#    }
}

Function _Run-CmakeBuildCommand ($btree, $bflavor, $bargs) {
    $cmd = "--build . $bargs --config $bflavor -- /m"
    _Run-Command $btree "cmake.exe" $cmd;
}

Function _Build-Project ([dwb.Project]$Project, [dwb.BuildContext]$BuildContext, $Generate, $Clean, $Build) {
    Write-Verbose "Building: $($Project.Name) $Clean $Build"

    $obj = $BuildContext.GetProjectBuildTree($Project);
    if ($Build) {
        Write-Verbose "Building: $($Project.Name)"

        if ($Generate -or (_Should-GenerateProject $Project $BuildContext)) {
            _Generate-Project $Project $BuildContext;
        }

        $bargs = "";
        if ($Clean) { $bargs += "--clean-first"; }
        _Run-CmakeBuildCommand $obj $BuildContext.Configuration $bargs;

    } elseif ($Generate) {
        _Generate-Project $Project $BuildContext;

    } elseif ($Clean) {
        Write-Verbose "Cleaning: $($Project.Name)"
        if ((Test-Path $obj) -and (gci $obj).Count -gt 0) {
            [void](del -Force -Recurse "$obj\*");
        }
    }
}

Function _Restore-NugetPackages {
    Param(
        [string]$NugetConfig,
        [string]$PackagesConfig,
        [string]$NugetFolder,
        [string]$PackagesFolder
    )
    Process {
        $packages = "$PackagesFolder\nuget.packages";

        # Ensure Nuget.exe is present
        $nugetExe = "$NugetFolder\nuget.exe";
        if (Test-Path $nugetExe) {
            iex "$nugetExe update -self";
        } else {
            Invoke-WebRequest https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile $nugetExe;
        }

        # Figure out if any VSTS sources are being used
        $xml = [xml](gc $NugetConfig);
        $vsts = $null;
        foreach ($src in $xml.SelectNodes("//packageSources/add")) {
            $i = $src.value.IndexOf(".pkgs.visualstudio.com");
            if ($i -ge 0) {
                $vsts = $src.value.substring(0,$i+22);
            }
        }

        # If so, ensure that we have the credential provider installed
        if ($vsts) {
            $credProvider = "$NugetFolder\CredentialProvider.VSS.exe";
            if (!(Test-Path $credProvider)) {
                $bundle = "$PackagesFolder\_VSTSCredProvider";
                if (!(Test-Path "$bundle.zip")) {
                    Invoke-WebRequest "$vsts/_apis/public/nuget/client/CredentialProviderBundle.zip" -OutFile "$bundle.zip";
                }
    
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory("$bundle.zip", $bundle);
                copy "$bundle\CredentialProvider.VSS.exe" $credProvider;
                rmdir -force -recurse $bundle;
                del "$bundle.zip";
            }
        }

        # Do the nuget restore to install the necessary packages
        if (Test-Path $PackagesConfig) {
            iex "$nugetExe install $PackagesConfig -ConfigFile $NugetConfig -OutputDirectory $packages"
    
            # Create symlinks to remove version info
            $allPackages = [xml](gc $PackagesConfig);
            foreach ($pkg in $allPackages.SelectNodes("//package")) {
                if ($pkg.shortname) {
                    $src = "$packages\$($pkg.id).$($pkg.version)";
                    if ($pkg.focus) { $src += "\$($pkg.focus)"; }
                    $dest = "$PackagesFolder\$($pkg.shortname)";
                    if (Test-Path $dest) { rd -Force -Recurse $dest; }
                    iex "cmd /c mklink /J $dest $src"
                }
            }
        }
    }
}

Function Build-Workbench {
    [CmdletBinding()]
    Param(
        [switch]$Purge,
        [switch]$Restore,
        [switch]$Nuke,
        [switch]$Clean,
        [switch]$Generate,
        [switch]$Build,
        [switch]$All
    )
    Process {
        if (!($Purge -or $Restore -or $Nuke -or $Clean -or $Generate -or $Build)) { $Build = $true; }

        $ctx = [dwb.BuildContext]::CurrentContext;
        $wb = $ctx.Workbench
        if (!$wb.ObjRoot) {
            throw "No workbench selected!";
        }

        # Select projects
        $Projects = $ctx.Projects | ?{ $_.Enabled -or $All };
        if ($Projects -eq $null -or $Projects.Count -eq 0) {
            throw "No projects selected!";
        }

        if ($Purge) {
            Write-Verbose "Purging workbench";
            if ((Test-Path "$($wb.ExtRoot)\lib") -and (gci "$($wb.ExtRoot)\lib").Count -gt 0) {
               [void](del -Force -Recurse "$($wb.ExtRoot)\lib\*");
            }
        }

        if ($Restore) {
            Write-Verbose "Restoring workbench";
            _Restore-NugetPackages -NugetConfig "$($wb.ExtRoot)\nuget.config" -PackagesConfig "$($wb.ExtRoot)\packages.config" -NugetFolder $wb.ExtRoot -PackagesFolder "$($wb.ExtRoot)\lib"
            _Populate-ExternalDependencies;
        }

        if ($Nuke) {
            Write-Verbose "Nuking workbench";
            if ($All) {
                if ((Test-Path $wb.ObjRoot) -and (gci $wb.ObjRoot).Count -gt 0) {
                    [void](del -Force -Recurse "$($wb.ObjRoot)\*");
                }
                if ((Test-Path $wb.BinRoot) -and (gci $wb.BinRoot).Count -gt 0) {
                    [void](del -Force -Recurse "$($wb.BinRoot)\*");
                }
            } else {
                $Projects | %{
                    $dir = $ctx.GetProjectBuildTree($_);
                    if (($dir.Length -gt $wb.ObjRoot.Length) -and (Test-Path $dir) -and (gci $dir).Count -gt 0) {
                        [void](del -Force -Recurse "$dir\*");
                    }
                }
            }
        }

        #TODO Track dependencies between projects so that they are built in order?
        if ($Generate -or $Build -or $Clean) {
            $Projects | %{ Write-Verbose $_.Name; _Build-Project $_ $ctx $Generate $Clean $Build }
        }

        if ($Test) {
            #TODO Unit Test
        }

        if ($Assemble) {
            #TODO Assemble functional packages
        }

        if ($Publish) {
            #TODO Publish local
        }
    }
}
set-alias build "Build-Workbench"
#Export-ModuleMember Build-Workbench

Function Get-Project {
    return (Get-BuildContext).Projects;
}

Function Enable-Project
{
    [CmdletBinding()]
    Param(
        [string]$Name
    )
    Process {
        (Get-BuildContext).Projects | ?{ $_.Name -eq $Name } | %{ $_.Enabled = $True; }
    }
}

Function Disable-Project
{
    [CmdletBinding()]
    Param(
        [string]$Name
    )
    Process {
        (Get-BuildContext).Projects | ?{ $_.Name -eq $Name } | %{ $_.Enabled = $False; }
    }
}

Function Launch-VisualStudio {
    $ctx = [dwb.BuildContext]::CurrentContext;
    Get-Project | ?{ $_.Enabled } | %{ gci ($ctx.GetProjectBuildTree($_)) *.sln | %{ Write-Verbose $_.FullName; start $_.FullName } }
}

# Building and stuff
Function _Build-Solution {
    [CmdletBinding()]
    Param(
        [string]$SolutionFile,
        [switch]$Purge,
        [switch]$Restore,
        [switch]$Clean,
        [switch]$Build,
        [switch]$Publish,
        [switch]$Assemble,
        [switch]$Full,
        [ValidateSet("x64", "x86")]
        [string]$Arch = "x64",
        [ValidateSet("Debug", "Release")]
        [string]$Flavor = "Debug",
        [ValidateSet("Quiet", "Minimal", "Normal", "Detailed", "Diagnostic")]
        [string]$LogLevel = "Normal"
    )
    Process {
        if (!$SolutionFile) {
            $here = pwd;
            $SolutionFile = gci $here *.sln
            while (!$SolutionFile) {
                $here = (Split-Path $here)
                if (!$here) { throw "Unable to find a Solution file"; }
                $SolutionFile = gci $here *.sln
            }
        }
        if (!$SolutionFile) {throw "Unable to find a Solution file"; }
        $SolutionFile = (gi $SolutionFile).FullName
        if (!$SolutionFile) {throw "Unable to find a Solution file"; }

        $slndir = Split-Path $SolutionFile
        $rootdir = Split-Path $slndir
        $NugetPackages = "$RootDir\NugetPackages"
        $NugetLocal = "$RootDir\Local"

        Function Run-BuildAction($sln, $action, $extras) {
            $msbuildcmd = "msbuild.exe $sln /p:Configuration=$Flavor $extras /p:Platform=$Arch $ba /clp:ShowCommandLine /m /fl /verbosity:$($LogLevel) /flp:LogFile=$($action)_$($Arch)_$($Flavor).log```;Verbosity=diagnostic```;ShowTimestamp"

            pushd ($slndir)
            $actualcmd = $msbuildcmd -f $action
            Write-Verbose "Running $actualcmd"
            iex $actualcmd
            popd
        }

        if ($Purge) {
            Write-Verbose "Purging $NugetPackages"
            rm -recurse "$NugetPackages\*.*"
            Write-Verbose "Purging $NugetLocal"
            rm -recurse "$NugetLocal\*.nupkg"
        }
        if ($Restore -or $Full) {
            Write-Verbose "Running $slndir\restore.cmd"
            iex "$slndir\restore.cmd"
        }
        if ($Clean -or $Full) {
            Run-BuildAction $SolutionFile Clean "/t:Clean"
        }
        if ($Build -or $Full) {
            Run-BuildAction $SolutionFile Build "/t:Build"
        }
        if ($Publish -or $Full) {
            Write-Verbose "Publishing $slndir\**\*.nupkg to $NugetLocal"
            gci -Recurse $slndir *.nupkg | % { copy $_.FullName $NugetLocal\. }
        }
        if ($Assemble -or $Full) {
            Run-BuildAction "$slndir\Assemble\Assemble.proj" Assemble "/p:OfficialBuild=true"
        }
    }
}

# Parameters:
# Build target (default: detect from folder; allow implicit context)
# Platform (aka "arch")
# Configuration (aka flavor)

# Actions:
# Restore (pulldeps), Purge
# Clean, Build, Test
# Assemble
# Publish Local, Publish Official

# For each selected target
# For each build context for the target
# Ensure build folder exists
# Ensure build params have not changed
