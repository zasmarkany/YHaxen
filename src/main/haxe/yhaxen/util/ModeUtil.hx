package yhaxen.util;

class ModeUtil
{
	public static function matches(modes:Array<String>, mode:String):Bool
	{
		if(modes == null)
			return true;
		if(mode == null && modes != null)
			return false;
		return Lambda.has(modes, mode);
	}
}