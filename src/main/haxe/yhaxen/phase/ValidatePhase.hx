package yhaxen.phase;

import yhaxen.enums.DependencyVersionType;
import yhaxen.enums.LogLevel;
import yhaxen.enums.SourceType;
import yhaxen.parser.ConfigParser;
import yhaxen.util.ArrayUtil;
import yhaxen.util.Git;
import yhaxen.util.Haxelib;
import yhaxen.util.System;
import yhaxen.valueObject.command.ValidateCommand;
import yhaxen.valueObject.config.Config;
import yhaxen.valueObject.dependency.Dependency;
import yhaxen.valueObject.dependency.DependencyTreeItem;
import yhaxen.valueObject.dependency.FlattenDependencies;
import yhaxen.valueObject.Error;

import sys.io.File;
import sys.FileSystem;

class ValidatePhase extends AbstractPhase<ValidateCommand>
{
	inline static var WORD_OK:String = "OK";
	inline static var WORD_MISSING:String = "MISSING";
	inline static var WORD_WARNING:String = "WARNING";
	inline static var WORD_INVALID:String = "INVALID";
	inline static var WORD_UNDEFINED:String = "UNDEFINED";
	inline static var WORD_UPDATE:String = "UPDATE";
	inline static var WORD_INSTALL:String = "INSTALL";

	public static function fromCommand(command:ValidateCommand):ValidatePhase
	{
		var config = ConfigParser.fromFile(command.configFile);
		return new ValidatePhase(config, command);
	}

	override function execute():Void
	{
		super.execute();

		if(config.dependencies == null || config.dependencies.length == 0)
			return logPhase("validate", "No dependencies found.");

		logPhase("validate", config.dependencies.length + " dependencies found");
		validateConfig();

		log(LogLevel.INFO, "");
		log(LogLevel.INFO, "resolving:");
		for(dependency in config.dependencies)
			resolveDependency(dependency);

		var list:Array<Dependency> = [];
		var tree = getTree();
		var flatten = flattenTree(tree);

		log(LogLevel.DEBUG, "");
		log(LogLevel.DEBUG, "dependency tree:");
		validateTree(tree);

		log(LogLevel.DEBUG, "");
		log(LogLevel.DEBUG, "flattened dependencies:");
		validateFlatten(flatten);

		log(LogLevel.DEBUG, "");
		log(LogLevel.DEBUG, "preparing current dependencies:");
		for(dependency in config.dependencies)
			prepareDependency(dependency);
	}

	function resolveDependency(dependency:yhaxen.valueObject.config.Dependency)
	{
		var exists:Bool = false;
		try
		{
			exists = haxelib.dependencyVersionExists(dependency.name, dependency.version);
		}
		catch(error:Dynamic)
		{
			throw new Error(
				"Invalid dependency " + dependency.name + ".",
				"Dependency directory " + dependency.version + " could not be resolved.",
				"Provide valid dependency version that can be resolved into a directory.");
		}

		if(exists && !dependency.update)
		{
			logKeyVal(LogLevel.INFO, dependency.toString(), 40, WORD_OK);
			return;
		}

		if(exists && dependency.update)
		{
			logKeyVal(LogLevel.INFO, dependency.toString(), 40, WORD_UPDATE);
			haxelib.removeDependencyVersion(dependency.name, dependency.version);
		}
		else
		{
			logKeyVal(LogLevel.INFO, dependency.toString(), 40, WORD_INSTALL);
		}

		switch(dependency.type)
		{
			case SourceType.GIT:
				installDependencyGit(dependency);
			case SourceType.HAXELIB:
				installDependencyHaxelib(dependency);
		}

		log(LogLevel.DEBUG, "");
	}

	function prepareDependency(dependency:yhaxen.valueObject.config.Dependency)
	{
		if(dependency.makeCurrent)
		{
			haxelib.makeCurrent(dependency.name, dependency.version);
			logKeyVal(LogLevel.DEBUG, dependency.toString(), 40, WORD_OK);
		}
	}

	function validateConfig():Void
	{
		var names:Array<String> = [];
		for(dependency in config.dependencies)
		{
			if(Lambda.has(names, dependency.name))
				throw new Error(
					"Misconfigured dependency " + dependency.name + "!",
					"Dependency " + dependency.name + " is defined multiple times.",
					"Provide only one definition for " + dependency.name + " in " + command.configFile + ".");

			names.push(dependency.name);
		}
	}

	function validateTree(list:Array<DependencyTreeItem>, level:Int=0):Void
	{
		for(item in list)
		{
			var result:String = WORD_INVALID;
			if(item.versionResolved != null)
				result = (item.versionResolvedExists ? WORD_OK : WORD_MISSING) + " (" + item.versionResolved + ")";

			var pad:String = StringTools.lpad("", " ", level * 2);
			logKeyVal(LogLevel.DEBUG, pad + item.toString(), 40, result);

			var detail = yhaxen.valueObject.config.Dependency.getFromList(config.dependencies, item.name);
			if(detail == null)
				throw new Error(
					"Undefined dependency " + item.name + "!",
					"Dependency " + item.name + " is not defined in " + command.configFile + ".",
					"Provide dependency details in " + command.configFile + ".");

			if(item.versionResolved == null)
				throw new Error(
					"Invalid dependency " + item.name + "!",
					"Dependency " + item.name + " has mismatched version used and can not be resolved.",
					"Provide forceVersion in " + command.configFile + " for this dependency.");

			if(!item.versionResolvedExists)
				throw new Error(
					"Missing dependency " + item.name + "!",
					"Dependency " + item.name + " with resolved version " + item.versionResolved + " is missing.",
					"Check dependency details in " + command.configFile + ".");

			if(item.dependencies != null)
				validateTree(item.dependencies, level + 1);
		}
	}

	function validateFlatten(data:FlattenDependencies):Void
	{
		var names:Array<String> = [];
		for(name in data.keys())
			names.push(name);
		names.sort(ArrayUtil.sortNames);

		for(name in names)
		{
			var dataName = data.get(name);
			var versions:Array<String> = [];
			for(version in dataName.keys())
				if(version != WORD_UNDEFINED && Lambda.indexOf(versions, version) == -1)
					versions.push(version);

			if(versions.length == 1)
			{
				logKeyVal(LogLevel.DEBUG, name, 40, WORD_OK + " (" + versions[0] + ")");
				continue;
			}

			logKeyVal(LogLevel.DEBUG, name, 40, WORD_WARNING);
			for(version in dataName.keys())
			{
				if(version == WORD_UNDEFINED)
					continue;
				var sources = dataName.get(version);
				for(source in sources)
					logKeyVal(LogLevel.DEBUG, "  in " + (source == null ? command.configFile : source.toString()), 40, " ! (" + version + ")");
			}

			var detail = yhaxen.valueObject.config.Dependency.getFromList(config.dependencies, name);
			if(detail == null || !detail.forceVersion)
				throw new Error(
					"Invalid dependency version for " + name + "!",
					"Dependency " + name + " has multiple versions used.",
					"Provide forceVersion in " + command.configFile + ".");
		}
	}

	function getTree():Array<DependencyTreeItem>
	{
		var result:Array<DependencyTreeItem> = [];
		for(dependency in config.dependencies)
		{
			var item = new DependencyTreeItem(dependency.name, dependency.version);
			updateMetadata(item);
			item.dependencies = getDependencyTree(item);
			result.push(item);
		}
		result.sort(DependencyTreeItem.sort);
		return result;
	}

	function flattenTree(list:Array<DependencyTreeItem>, parent:DependencyTreeItem=null,
		target:FlattenDependencies=null):FlattenDependencies
	{
		if(list == null || list.length == 0)
			return null;

		if(target == null)
			target = new FlattenDependencies();

		for(dependency in list)
		{
			if(!target.exists(dependency.name))
				target.set(dependency.name, new Map<String,Array<DependencyTreeItem>>());
			var targetName = target.get(dependency.name);
			var version = dependency.version == null ? WORD_UNDEFINED : dependency.version;
			if(!targetName.exists(version))
				targetName.set(version, []);
			var targetNameVersion = targetName.get(version);
			if(!DependencyTreeItem.listContainsByNameAndVersion(targetNameVersion, parent))
				targetNameVersion.push(parent);
			flattenTree(dependency.dependencies, dependency, target);
		}

		return target;
	}

	function installDependencyGit(dependency:yhaxen.valueObject.config.Dependency):Void
	{
		var directory = haxelib.getGitDependencyDirectory(dependency.name);
		prepareGitDirectory(dependency, directory);

		try
		{
			Git.fetchAll(directory, logGit);
			Git.checkout(dependency.version, directory, logGit);
			try
			{
				// in case we were in branch already pull is required after fetch
				Git.pull(directory, logGit);
			}
			catch(error:Dynamic){}
		}
		catch(error:Dynamic)
		{
			System.deleteDirectory(directory);
			throw error;
		}

		var depenencyDirectory:String = haxelib.getDependencyDirectory(dependency.name);
		System.createDirectory(depenencyDirectory);

		var target:String = haxelib.getDependencyVersionDirectory(dependency.name, dependency.version, null);

		if(dependency.subdirectory == null)
		{
			System.copyDirectory(directory, target);
			System.deleteDirectory(target + "/.git");
		}
		else
		{
			System.copyDirectory(directory + "/" + dependency.subdirectory, target);
		}

		var currentFile:String = depenencyDirectory + "/" + Haxelib.FILE_CURRENT;
		if(!FileSystem.exists(currentFile))
			File.saveContent(currentFile, dependency.version);
	}

	function prepareGitDirectory(dependency:yhaxen.valueObject.config.Dependency, directory:String):Void
	{
		if(!FileSystem.exists(directory))
		{
			Git.clone(dependency.source, directory, logGit);
			return;
		}

		if(!FileSystem.isDirectory(directory))
		{
			System.deleteDirectory(directory);
			Git.clone(dependency.source, directory, logGit);
			return;
		}

		var remoteOriginUrl:String;
		try
		{
			remoteOriginUrl = Git.getRemoteOriginUrl(directory, logGit);
		}
		catch(error:Dynamic)
		{
			System.deleteDirectory(directory);
			throw error;
		}

		if(remoteOriginUrl != dependency.source)
		{
			System.deleteDirectory(directory);
			Git.clone(dependency.source, directory, logGit);
		}
	}

	function installDependencyHaxelib(dependency:Dependency):Void
	{
		if(systemCommand(LogLevel.DEBUG, "haxelib", ["install", dependency.name, dependency.version]) != 0)
			throw new Error(
				"Invalid haxelib dependency " + dependency.name + " version " + dependency.version + "!",
				"Haxelib could not install " + dependency.name + " with version " + dependency.version + ".",
				"Make sure dependency name and version is correctly defined in " + command.configFile + ".");
	}

	function getDependencyTree(dependency:Dependency):Array<DependencyTreeItem>
	{
		var directory:String = haxelib.getDependencyVersionDirectory(dependency.name, dependency.versionResolved,
			dependency.versionType);

		if(directory == null)
			return null;

		var list = haxelib.getDependencyData(directory);
		if(list == null)
			return null;

		var result:Array<DependencyTreeItem> = [];
		for(info in list.dependencies)
		{
			var item = new DependencyTreeItem(info.project, info.version);
			updateMetadata(item);
			item.dependencies = item.exists ? getDependencyTree(item) : null;
			result.push(item);
		}
		result.sort(DependencyTreeItem.sort);
		return result;
	}

	function updateMetadata(dependency:Dependency):Void
	{
		var detail = yhaxen.valueObject.config.Dependency.getFromList(config.dependencies, dependency.name);
		dependency.exists = haxelib.dependencyExists(dependency.name);

		if(dependency.exists && haxelib.getDependencyIsDev(dependency.name))
			dependency.versionType = DependencyVersionType.DEV;
		else if(dependency.version == null)
			dependency.versionType = DependencyVersionType.ANY;
		else
			dependency.versionType = DependencyVersionType.REGULAR;

		dependency.versionResolved = (detail != null && detail.forceVersion) ? detail.version : dependency.version;

		dependency.versionResolvedExists = dependency.versionResolved != null
			&& dependency.exists
			&& haxelib.dependencyVersionExists(dependency.name, dependency.versionResolved);
	}
}