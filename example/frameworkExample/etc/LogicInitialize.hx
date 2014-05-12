package frameworkExample.etc;
/**
 * 初期化用に使われるシーン
 * 
 * @auther sipo
 */
import jp.sipo.gipo.core.Gear.GearDispatcherKind;
import frameworkExample.context.LogicToView;
import frameworkExample.context.LogicScene;
import frameworkExample.scene.mock0.Mock0;
/* ================================================================
 * 設定
 * ===============================================================*/
/* ================================================================
 * 動作
 * ===============================================================*/
class LogicInitialize extends LogicScene
{
	
	/** コンストラクタ */
	public function new() { super(); }
	
	@:handler(GearDispatcherKind.Run)
	private function run():Void
	{
		changeViewScene(ViewSceneKind.Blank, ViewSceneOrder);
		// すぐにシーン移動
		logic.changeState(new Mock0());
	}
}
