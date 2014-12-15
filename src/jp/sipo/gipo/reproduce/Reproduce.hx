package jp.sipo.gipo.reproduce;
/**
 * 動作コマンドの記録と再生を担当する。
 * 
 * @auther sipo
 */
import jp.sipo.gipo.core.config.GearNoteTag;
import jp.sipo.gipo.reproduce.LogWrapper;
import jp.sipo.gipo.reproduce.LogPart;
import haxe.PosInfos;
import jp.sipo.gipo.core.GearDiffuseTool;
import jp.sipo.gipo.core.state.StateGearHolder;
import jp.sipo.gipo.core.state.StateSwitcherGearHolderImpl;
import jp.sipo.gipo.core.Gear.GearDispatcherKind;
import jp.sipo.util.Note;
import haxe.ds.Option;
/* ================================================================
 * Hookに要求する機能
 * ===============================================================*/
interface HookForReproduce
{
	/** イベントの実行 */
	public function executeEvent(logWay:LogwayKind, factorPos:PosInfos):Void;
}
/* ================================================================
 * OperationHookに要求する機能
 * ===============================================================*/
interface OperationHookForReproduce
{
	/**
	 * Reproduceからのイベント処理
	 */
	public function noticeReproduceEvent(event:ReproduceEvent):Void;
}
/**
 * OperationLogic向けのイベント定義
 */
enum ReproduceEvent
{
	/** ログの更新あり */
	LogUpdate;
}
/* ================================================================
 * 実装
 * ===============================================================*/
class Reproduce<TUpdateKind> extends StateSwitcherGearHolderImpl<ReproduceState<TUpdateKind>>
{
	@:absorb
	private var operationHook:OperationHookForReproduce;
	@:absorb
	private var hook:HookForReproduce;
	/* 記録担当 */
	private var recorder:ReproduceRecord<TUpdateKind>;
	/* 再生フェーズ */
	private var phase:Option<ReproducePhase<TUpdateKind>> = Option.None;
	/* 再生可能かどうかの判定 */
	private var canProgress:Bool = true;
	/* フレームカウント */
	private var frame:Int = 0;
	/* 再生予約 */
	private var bookReplay:BookReplay<TUpdateKind> = BookReplay.None;
	
	
	private var note:Note;
	
	/** コンストラクタ */
	public function new() 
	{
		super();
	}
	
	@:handler(GearDispatcherKind.Diffusible)
	private function diffusible(tool:GearDiffuseTool):Void
	{
		// 下位層にNoteを渡す
		note = new Note([GearNoteTag.Reproduce]);
		tool.diffuse(note, Note);
	}
	
	@:handler(GearDispatcherKind.Run)
	private function run():Void
	{
		// 記録開始
		startRecord();
		// 再生は待機状態へ
		stateSwitcherGear.changeState(new ReproduceReplayWait<TUpdateKind>(executeEvent));
	}
	
	/* 記録の開始 */
	private function startRecord():Void
	{
		recorder = gear.addChild(new ReproduceRecord());
	}
	
	/**
	 * 再生可能かどうかを確認して状態を切り替える
	 */
	public function checkCanProgress():Bool
	{
		canProgress = state.checkCanProgress();
		return canProgress;
	}
	
	/**
	 * 更新
	 */
	public function update():Void
	{
		if (!canProgress) return;
		// フレームの進行
		frame++;
		// replayerの進行
		state.update(frame);
	}
	
	// TODO:<<尾野>>implを使わないことでstateの名称を正しく
	
	/**
	 * フレーム間のフェーズ切り替え
	 */
	public function startOutFramePhase():Void
	{
		startPhase(ReproducePhase.OutFrame);
	}
	/**
	 * フレーム内のフェーズ切り替え
	 */
	public function startInFramePhase(TUpdateKind:TUpdateKind):Void
	{
		startPhase(ReproducePhase.InFrame(TUpdateKind));
	}
	/* フェーズ切り替え共通動作 */
	private function startPhase(nextPhase:ReproducePhase<TUpdateKind>):Void
	{
		switch(phase)
		{
			case Option.None : this.phase = Option.Some(nextPhase);	// 新しいPhaseに切り替える
			case Option.Some(v) : throw '前回のフェーズが終了していません $v->$nextPhase';
		}
	}
	
	
	
	/**
	 * イベントの発生を受け取る
	 */
	public function noticeLog(logway:LogwayKind, factorPos:PosInfos):Void
	{
		var phaseValue:ReproducePhase<TUpdateKind> = switch(phase)
		{
			case Option.None : throw 'フェーズ中でなければ記録できません $phase';
			case Option.Some(v) : v;
		}
		// メイン処理
		Note.temporal('replay update $frame $canProgress');
		var logPart:LogPart<TUpdateKind> = new LogPart<TUpdateKind>(phaseValue, frame, logway, factorPos);
		state.noticeLog(logPart, canProgress);
	}
	
	// MEMO:フェーズ終了で実行されるのはリプレイの時のみで、通常動作時は、即実行される
	/*
	理由
	確かに、両方共endにしておくことで、統一性が担保されるが、
	・コマンドに起因して更にコマンドが発生する場合に問題になる。
	・コマンドを受け取ったLogicがViewにボタンの無効命令を出しても間に合わない
	・スタックトレースが悪化する
	といったデメリットがある。
	それに対して、通常時にendでないタイミングで発生する場合でも、少し不安な程度で、
	順序は確保され、ViewからのLogicへのデータはロックされているはずなので明確なデメリットは無いはず
	 */
	
	/**
	 * フェーズ終了
	 */
	public function endPhase():Void
	{
		var phaseValue:ReproducePhase<TUpdateKind> =switch(phase)
		{
			case Option.None : throw '開始していないフェーズを終了しようとしました $phase';
			case Option.Some(value) : value;
		}
		
		// ここから再生モードに移行する可能性を調べる
		if (Type.enumEq(phaseValue, ReproducePhase.OutFrame))
		{
			switch(bookReplay)
			{
				case BookReplay.None:
				case BookReplay.Book(log): startReplay_(log);
			}
		}
		// OutFrameの時は、ここから再生モードに移行する可能性を調べる
//		if (phaseIsOutFrame)
//		{
//			// 必要ならReplayへ以降
//			var stateSwitchWay:ReproduceSwitchWay<TUpdateKind> = state.getChangeWay();
//			switch (stateSwitchWay)
//			{
//				case ReproduceSwitchWay.None :
//				case ReproduceSwitchWay.ToReplay(log) : stateSwitcherGear.changeState(new ReproduceReplay(log, executeEvent));
//			}
//		}
// startRecord
		// メイン処理
		state.endPhase(phaseValue, canProgress);
		// フェーズを無しに
		phase = Option.None;
	}
	/* 再生を開始 */
	private function startReplay_(log:ReplayLog<TUpdateKind>):Void
	{
		// 予約を消す
		bookReplay = BookReplay.None;
		// 記録ログをリセットして記録しなおし
		startRecord();
		// 再生を開始
		stateSwitcherGear.changeState(new ReproduceReplay(log, executeEvent));
	}
	/* イベントを実際に実行する処理 */
	private function executeEvent(part:LogPart<TUpdateKind>):Void
	{
		// 保存
		recorder.saveLog(part);
		// 実行
		hook.executeEvent(part.logway, part.factorPos);
	}
	
	/**
	 * ログを返す
	 */
	public function getRecordLog():RecordLog<TUpdateKind>
	{
		return recorder.getRecordLog();
	}
	
	/**
	 * 再生状態に切り替える
	 */
	public function startReplay(log:ReplayLog<TUpdateKind>, logIndex:Int):Void
	{
		frame = 0;
		log.setPosition(logIndex);
		bookReplay = BookReplay.Book(log);
//		note.log('replayStart($logIndex) $log');
//		log.setPosition(logIndex);
//		frame = -1;
//		stateSwitcherGear.changeState(new ReproduceReplay(log, executeEvent));
	}
}
interface ReproduceState<TUpdateKind> extends StateGearHolder
{
	/**
	 * 進行可能かどうかチェックする
	 */
	public function checkCanProgress():Bool;
	
	/**
	 * 更新処理
	 */
	public function update(frame:Int):Void;
	
	/**
	 * ログ発生の通知
	 */
	public function noticeLog(logPart:LogPart<TUpdateKind>, canProgress:Bool):Void;
	
	/**
	 * フェーズ終了
	 */
	public function endPhase(phaseValue:ReproducePhase<TUpdateKind>, canProgress:Bool):Void;
}
enum BookReplay<TUpdateKind>
{
	None;
	Book(replayLog:ReplayLog<TUpdateKind>);
}
