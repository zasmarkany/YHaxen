package sk.yoz.yhaxen.util;

import sk.yoz.yhaxen.valueObject.Error;

class Git
{
	public static function checkout(source:String, branch:String, directory:String):Void
	{
		var cwd = Sys.getCwd();

		if(System.command("git", ["clone", "--quiet", source, directory]) != 0)
			throw new Error(
				"Git clone failed.",
				"Git command is not configured or repository does not exist.",
				"Make sure git is configured and repository exists.");

		Sys.setCwd(directory);

		if(System.command("git", ["checkout", "--quiet", "-b", "yhaxen-" + branch, branch]) != 0)
			throw new Error(
				"Git checkout failed.",
				"Git was not able to checkout branch, tag or commit " + branch + ".",
				"Make sure " + branch + " exists in git repository.");

		Sys.setCwd(cwd);
	}

	public static function release(version:String):Void
	{
		/*
		git rev-parse HEAD
				1fefe60dff297a8aaa8357d0cc87df6cf8ff70d6

		git add src/main/haxe/haxelib.json
		git commit -m "YHaxen prepares release $version"
		git tag -a $version -m "YHaxen release $version"
		git checkout 1fefe60dff297a8aaa8357d0cc87df6cf8ff70d6 src/main/haxe/haxelib.json
		git add src/main/haxe/haxelib.json
		git commit -m "YHaxen reverting files $version"
		git push origin --tags

		if(System.command("git", ["tag", "-a", version, "-m", "YHaxen release " + version]) != 0)
			throw new Error(
				"Git tag failed.",
				"Git was not able to create tag " + version + ".",
				"Make sure project is under git control and current user has suffucient rights.");

		git push origin --tags
		*/
	}
}