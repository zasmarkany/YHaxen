package sk.yoz.yhaxen.helpers;

class SysHelper
{
	public static function printCommand(title:String):Void
	{
		printRow("-", "- " + title + " ");
	}

	static function printRow(fill:String, message:String=null):Void
	{
		print(StringTools.rpad(message == null ? "" : message, fill, 79));
	}

	public static function print(message:String):Void
	{
		Sys.println(message);
	}

	public static function printKeyVal(key:String, pad:Int, value:String):Void
	{
		Sys.println(StringTools.rpad(key, " ", pad) + value);
	}

	public static function command(cmd:String, args:Array<String>):Int
	{
		print("  $ " + cmd + " " + args.join(" "));
		return Sys.command(cmd, args);
	}
}