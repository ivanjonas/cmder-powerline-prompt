-- Source: https://github.com/ivanjonas/cmder-powerline-prompt
-- Original: https://github.com/AmrEldib/cmder-powerline-prompt 

--- pathLength is whether the displayed prompt is the full path or only the folder name
 -- Use:
 -- "full" for full path like C:\Windows\System32
local pathLengthFull = "full"
 -- "folder" for folder name only like System32
local pathLengthFolder = "folder"
 -- default is pathLengthFull
local pathLength = pathLengthFull

local prompts = { '', 'λ', '', '', '', '', '', '', '', '', '', '', '', 'ﲹ', 'ﳀ', 'ﱫ', '', '', '', '' }

local symbols = {
    arrow = "",
    branch = "",
    merge = "",
    home = "",
    ahead = "⯅",
    behind = "⯆"
}

local function get_folder_name(path)
	local reversePath = string.reverse(path)
	local slashIndex = string.find(reversePath, "\\")
	return string.sub(path, string.len(path) - slashIndex + 2)
end

---
-- Find out current branch
-- @return {nil|git branch name}
---
local function get_git_branch(git_dir)
    git_dir = git_dir or get_git_dir()

    -- If git directory not found then we're probably outside of repo
    -- or something went wrong. The same is when head_file is nil
    local head_file = git_dir and io.open(git_dir..'/HEAD')
    if not head_file then return end

    local HEAD = head_file:read()
    head_file:close()

    -- if HEAD matches branch expression, then we're on named branch
    -- otherwise it is a detached commit
    local branch_name = HEAD:match('ref: refs/heads/(.+)')

    return branch_name or 'HEAD detached at '..HEAD:sub(1, 7)
end

function getRandomPrompt(ostime)
    math.randomseed( ostime )
    local rand = math.random( 1, #prompts )
    return prompts[rand]
end

-- Resets the prompt 
function lambda_prompt_filter()
    cwd = clink.get_cwd()
	if pathLength == pathLengthFolder then
		cwd =  get_folder_name(cwd)
	end
    local ostime = os.time()
    prompt = "\x1b[30;42m "..getRandomPrompt(ostime).." {cwd} {git}\n\x1b[32;40m {prompt} \x1b[0m"
    new_value = string.gsub(prompt, "{cwd}", cwd)
    clink.prompt.value = string.gsub(new_value, "{prompt}", getRandomPrompt(ostime))
end

--- copied from clink.lua
 -- Resolves closest directory location for specified directory.
 -- Navigates subsequently up one level and tries to find specified directory
 -- @param  {string} path    Path to directory will be checked. If not provided
 --                          current directory will be used
 -- @param  {string} dirname Directory name to search for
 -- @return {string} Path to specified directory or nil if such dir not found
local function get_dir_contains(path, dirname)

    -- return parent path for specified entry (either file or directory)
    local function pathname(path)
        local prefix = ""
        local i = path:find("[\\/:][^\\/:]*$")
        if i then
            prefix = path:sub(1, i-1)
        end
        return prefix
    end

    -- Navigates up one level
    local function up_one_level(path)
        if path == nil then path = '.' end
        if path == '.' then path = clink.get_cwd() end
        return pathname(path)
    end

    -- Checks if provided directory contains git directory
    local function has_specified_dir(path, specified_dir)
        if path == nil then path = '.' end
        local found_dirs = clink.find_dirs(path..'/'..specified_dir)
        if #found_dirs > 0 then return true end
        return false
    end

    -- Set default path to current directory
    if path == nil then path = '.' end

    -- If we're already have .git directory here, then return current path
    if has_specified_dir(path, dirname) then
        return path..'/'..dirname
    else
        -- Otherwise go up one level and make a recursive call
        local parent_path = up_one_level(path)
        if parent_path == path then
            return nil
        else
            return get_dir_contains(parent_path, dirname)
        end
    end
end

-- copied from clink.lua
-- clink.lua is saved under %CMDER_ROOT%\vendor
local function get_git_dir(path)

    -- return parent path for specified entry (either file or directory)
    local function pathname(path)
        local prefix = ""
        local i = path:find("[\\/:][^\\/:]*$")
        if i then
            prefix = path:sub(1, i-1)
        end
        return prefix
    end

    -- Checks if provided directory contains git directory
    local function has_git_dir(dir)
        return clink.is_dir(dir..'/.git') and dir..'/.git'
    end

    local function has_git_file(dir)
        local gitfile = io.open(dir..'/.git')
        if not gitfile then return false end

        local git_dir = gitfile:read():match('gitdir: (.*)')
        gitfile:close()

        return git_dir and dir..'/'..git_dir
    end

    -- Set default path to current directory
    if not path or path == '.' then path = clink.get_cwd() end

    -- Calculate parent path now otherwise we won't be
    -- able to do that inside of logical operator
    local parent_path = pathname(path)

    return has_git_dir(path)
        or has_git_file(path)
        -- Otherwise go up one level and make a recursive call
        or (parent_path ~= path and get_git_dir(parent_path) or nil)
end

---
 -- True if the repo is clean, False otherwise
 -- @return {bool}
---
function is_git_clean()
    local file = io.popen("git --no-optional-locks status --porcelain 2>nul")
    for line in file:lines() do
        file:close()
        return false
    end
    file:close()
    return true
end

function is_git_merging(git_dir)
    local merge_file = git_dir and io.open(git_dir..'/MERGE_HEAD')
    if not merge_file then
        return false
    else
        merge_file:close()
        return true
    end
end

function get_ahead_and_behind()
    local symbolicRefPipe = io.popen("git symbolic-ref HEAD")
    local symbolicRef = symbolicRefPipe:lines()()
    symbolicRefPipe:close()

    if string.find(symbolicRef, "fatal", 1, true) then
        -- guard against catastrophic git problem
        return ""
    end

    local branch = string.sub(symbolicRef, 12)
    local remotePipe = io.popen((string.gsub("git config branch.{branch}.remote", "{branch}", branch)))
    local remote = remotePipe:lines()()
    remotePipe:close()

    if not remote then
        -- guard against branches without remotes
        return ""
    end

    -- we have a branch with a remote, which is possibly local
    local remoteRef
    local mergePipe = io.popen((string.gsub("git config branch.{branch}.merge", "{branch}", branch)))
    local merge = mergePipe:lines()()
    mergePipe:close()

    if remote == '.' then -- "local"
        remoteRef = merge
    else
        remoteRef = "refs/remotes/"..remote.."/"..(string.sub(merge, 12))
    end

    local ahead = 0
    local behind = 0
    local revListPipe = io.popen(("git rev-list --left-right "..remoteRef.."...HEAD"))
    for revListLine in revListPipe:lines() do
        local firstString = string.sub(revListLine, 1, 1)
        if firstString == "<" then
            behind = behind + 1
        elseif firstString == ">" then
            ahead = ahead + 1
        end
    end
    revListPipe:close()

    if ahead > 0 then
        return " "..symbols.ahead..ahead
    elseif behind > 0 then
        return " "..symbols.behind..behind
    end

    return ""
end

-- adopted from clink.lua
-- Modified to add colors and arrow symbols
function colorful_git_prompt_filter()

    -- Colors for git status
    local colors = {
		--         arrow;next segment             font;segment
        clean = "\x1b[32;44m"..symbols.arrow.."\x1b[37;44m ",
        dirty = "\x1b[32;43m"..symbols.arrow.."\x1b[30;43m ",
        merge = "\x1b[32;43m"..symbols.arrow.."\x1b[30;43m ",
    }

    local closingcolors = {
        clean = " \x1b[34;40m"..symbols.arrow,
        dirty = " ± \x1b[33;40m"..symbols.arrow,
        merge = " \x1b[33;41m"..symbols.arrow.."\x1b[37;41m "..symbols.merge.." \x1b[31;40m"..symbols.arrow,
    }

    local git_dir = get_git_dir()
    if git_dir then
        -- if we're inside of git repo then try to detect current branch
        local branch = get_git_branch(git_dir)
        if branch then
            -- Has branch => therefore it is a git folder, now figure out status
            if is_git_clean() then
                color = colors.clean
                closingcolor = closingcolors.clean
            elseif is_git_merging(git_dir) then
                color = colors.merge
                closingcolor = closingcolors.merge
            else
                color = colors.dirty
                closingcolor = closingcolors.dirty
            end

            clink.prompt.value = string.gsub(clink.prompt.value, "{git}", color..symbols.branch.." "..branch..get_ahead_and_behind()..closingcolor)
            return false
        end
    end

    -- No git present or not in git file
    clink.prompt.value = string.gsub(clink.prompt.value, "{git}", "\x1b[32;40m"..symbols.arrow)
    return false
end

-- override the built-in filters
clink.prompt.register_filter(lambda_prompt_filter, 55)
clink.prompt.register_filter(colorful_git_prompt_filter, 60)
