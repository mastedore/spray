--!strict
-->> Installer.luau
--> Puts Spray into the open place at ReplicatedStorage.Packages.Spray, replacing whatever
--> version is there, and takes it out again.
-->
--> The newest version comes straight from GitHub. The branch's latest commit is looked up,
--> every file under Spray/ at that commit is downloaded, and the ModuleScripts are rebuilt
--> from them the way Rojo would: init.luau is the package itself, every other file a child
--> named after it, folders nest. Everything is fetched from that one commit, so a push that
--> lands halfway through can't leave a mix of two versions.
-->
--> When GitHub can't be reached (no connection, the repository still private, or the
--> permission Studio asks for the first time a plugin makes a request was declined), the
--> copy of Spray inside the plugin goes in instead, and the output says so. That's the
--> version the plugin was built with.
-->
--> Either way the new tree is built in full first and only swapped in at the end, inside a
--> single undo step, so a failed download never leaves a half replaced package behind.
-->
--> The installed module is tagged with where it came from (InstalledFrom, plus Commit and
--> Version when it's from GitHub), which answers "which Spray is this place on" at a glance.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

const REPOSITORY = "mastedore/spray"
const BRANCH = "main"
const FOLDER = "Spray"

const API = `https://api.github.com/repos/{REPOSITORY}`
const RAW = `https://raw.githubusercontent.com/{REPOSITORY}`

--- File suffix -> the Instance it becomes, longest suffixes first so ".server.luau" wins
--- over ".luau".
const KINDS: { { Suffix: string, Class: string } } = {
	{ Suffix = ".server.luau", Class = "Script" },
	{ Suffix = ".client.luau", Class = "LocalScript" },
	{ Suffix = ".server.lua", Class = "Script" },
	{ Suffix = ".client.lua", Class = "LocalScript" },
	{ Suffix = ".luau", Class = "ModuleScript" },
	{ Suffix = ".lua", Class = "ModuleScript" },
}

type File = {
	Path: string, -- relative to Spray/, with forward slashes
	Source: string,
}

local Installer = {}

-- -- Downloading ---------------------------------------------------------------

local function Get(Url: string, Accept: string?): string
	local response = HttpService:RequestAsync({
		Url = Url,
		Method = "GET",
		Headers = if Accept then { Accept = Accept } else nil,
	})
	if not response.Success then
		error(`{response.StatusCode} {response.StatusMessage} from {Url}`, 0)
	end
	return response.Body
end

local function Api(Path: string): any
	return HttpService:JSONDecode(Get(API .. Path, "application/vnd.github+json"))
end

--- Each path segment escaped on its own, so the slashes survive.
local function Escape(Path: string): string
	local parts = {}
	for part in string.gmatch(Path, "[^/]+") do
		table.insert(parts, HttpService:UrlEncode(part))
	end
	return table.concat(parts, "/")
end

local function Classify(FileName: string): (string?, string?)
	for _, kind in KINDS do
		local suffix = kind.Suffix
		if #FileName > #suffix and string.sub(FileName, -#suffix) == suffix then
			return string.sub(FileName, 1, -#suffix - 1), kind.Class
		end
	end
	return nil, nil
end

local function Download(): ({ File }, string, string?)
	local branch = Api(`/branches/{BRANCH}`)
	local commit: string = branch.commit.sha

	local tree = Api(`/git/trees/{commit}?recursive=1`)
	if tree.truncated then
		error("the repository tree is too big for one listing", 0)
	end

	local prefix = FOLDER .. "/"
	local files: { File } = {}
	for _, entry in tree.tree do
		local path: string = entry.path
		if entry.type ~= "blob" or string.sub(path, 1, #prefix) ~= prefix then
			continue
		end
		local fileName = string.match(path, "[^/]+$") or path
		if not Classify(fileName) then
			continue
		end
		table.insert(files, {
			Path = string.sub(path, #prefix + 1),
			Source = Get(`{RAW}/{commit}/{Escape(path)}`),
		})
	end

	-- The version is a nicety; a missing or odd wally.toml doesn't stop the install.
	local version: string? = nil
	pcall(function()
		local manifest = Get(`{RAW}/{commit}/wally.toml`)
		version = string.match(manifest, '\nversion%s*=%s*"([^"]+)"')
	end)

	return files, commit, version
end

-- -- Building ------------------------------------------------------------------

--- Rebuilds the package from its files. Nothing is parented into the place here.
local function Assemble(Files: { File }): Instance
	table.sort(Files, function(A, B)
		return A.Path < B.Path
	end)

	-- One Instance per directory ("" is Spray/ itself). A directory with an init file
	-- becomes that script; any other is a Folder.
	local directories: { [string]: Instance } = {}
	local loose: { { Directory: string, Name: string, Class: string, Source: string } } = {}

	for _, file in Files do
		local above, last = string.match(file.Path, "^(.*)/([^/]+)$")
		local directory: string = above or ""
		local name, class = Classify(last or file.Path)
		if not (name and class) then
			continue
		end
		if name == "init" then
			local node = Instance.new(class) :: any
			node.Source = file.Source
			directories[directory] = node
		else
			table.insert(loose, { Directory = directory, Name = name, Class = class, Source = file.Source })
		end
	end

	local root = directories[""]
	if not (root and root:IsA("ModuleScript")) then
		error(`{FOLDER}/init.luau is missing`, 0)
	end

	local function Above(Path: string): string
		return string.match(Path, "^(.*)/[^/]+$") or ""
	end

	-- Every directory on the way down to a file needs an Instance, including the ones that
	-- only hold other directories. Made up front so nothing is added while iterating.
	local function Ensure(Path: string)
		if directories[Path] then
			return
		end
		directories[Path] = Instance.new("Folder")
		Ensure(Above(Path))
	end
	for _, entry in loose do
		Ensure(entry.Directory)
	end
	local paths: { string } = {}
	for path in directories do
		table.insert(paths, path)
	end
	for _, path in paths do
		if path ~= "" then
			Ensure(Above(path))
		end
	end

	for _, entry in loose do
		local node = Instance.new(entry.Class) :: any
		node.Name = entry.Name
		node.Source = entry.Source
		node.Parent = directories[entry.Directory]
	end
	for path, node in directories do
		if path ~= "" then
			node.Name = string.match(path, "[^/]+$") or path
			node.Parent = directories[Above(path)]
		end
	end

	root.Name = "Spray"
	return root
end

-- -- Placing -------------------------------------------------------------------

function Installer.Find(): Instance?
	local packages = ReplicatedStorage:FindFirstChild("Packages")
	return packages and packages:FindFirstChild("Spray")
end

local function Swap(Package: Instance)
	local recording = ChangeHistoryService:TryBeginRecording("Install Spray")

	local packages = ReplicatedStorage:FindFirstChild("Packages")
	if not packages then
		local folder = Instance.new("Folder")
		folder.Name = "Packages"
		folder.Parent = ReplicatedStorage
		packages = folder
	end
	local target = packages :: Instance

	local existing = target:FindFirstChild("Spray")
	if existing then
		existing:Destroy()
	end
	Package.Name = "Spray"
	Package.Parent = target

	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
end

--- Installs the latest Spray from GitHub, or `Bundled` when that fails. Yields while it
--- downloads. Returns what happened, for the output.
function Installer.Install(Bundled: Instance): string
	local replacing = Installer.Find() ~= nil

	local where = if replacing then "replacing the one that was there" else "at ReplicatedStorage.Packages.Spray"

	local ok, result = pcall(function(): string
		local files, commit, version = Download()
		local package = Assemble(files)
		package:SetAttribute("InstalledFrom", "GitHub")
		package:SetAttribute("Commit", commit)
		if version then
			package:SetAttribute("Version", version)
		end
		Swap(package)
		local name = if version then `Spray {version}` else "Spray"
		return `{name} ({string.sub(commit, 1, 7)}) installed from GitHub, {where}.`
	end)
	if ok then
		return result
	end

	local copy = Bundled:Clone()
	copy:SetAttribute("InstalledFrom", "Plugin")
	Swap(copy)
	return `Couldn't get Spray from GitHub ({result}), so the copy inside the plugin went in instead, {where}.`
end

--- Takes Spray out, and the Packages folder with it when that leaves it empty.
function Installer.Remove(): string
	local installed = Installer.Find()
	if not installed then
		return "Spray isn't installed in this place."
	end
	local packages = installed.Parent :: Instance

	local recording = ChangeHistoryService:TryBeginRecording("Remove Spray")
	installed:Destroy()
	if #packages:GetChildren() == 0 then
		packages:Destroy()
	end
	if recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	end
	return "Removed ReplicatedStorage.Packages.Spray."
end

return Installer
