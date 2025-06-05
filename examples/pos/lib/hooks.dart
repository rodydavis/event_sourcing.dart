import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:signals/signals_flutter.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';

const _memoryPath = ':memory:';
CommonDatabase useDatabase({
  String path = _memoryPath,
  String? vfs,
  OpenMode mode = OpenMode.readWriteCreate,
  bool uri = false,
  bool? mutex,
}) {
  return useMemoized(() {
    final d =
        path == _memoryPath
            ? sqlite3.openInMemory(vfs: vfs)
            : sqlite3.open(path, vfs: vfs, mode: mode, uri: uri, mutex: mutex);
    return d;
  });
}

class SqliteQuerySignal extends FlutterSignal<ResultSet> {
  final CommonDatabase db;
  final ReadonlySignal<String> sql;
  final ReadonlySignal<List<Object?>> args;

  SqliteQuerySignal(this.db, this.sql, this.args)
    : super(db.select(sql(), args())) {
    final sub = db.updates.listen((event) {
      execute();
    }, cancelOnError: false);
    onDispose(sub.cancel);
    onDispose(effect(execute));
  }

  void execute() {
    value = db.select(sql(), args());
  }
}

ReadonlySignal<List<Row>> useQuery(
  CommonDatabase db,
  String sql, [
  List<Object?> args = const [],
]) {
  final s = useSignal(sql);
  final a = useSignal(args);
  return useExistingSignal(SqliteQuerySignal(db, s, a));
}

ReadonlySignal<Row> useQuerySingle(
  CommonDatabase db,
  String sql, [
  List<Object?> args = const [],
]) {
  final q = useQuery(db, sql, args);
  return useComputed(() => q.value.single);
}

ReadonlySignal<Row?> useQuerySingleOrNull(
  CommonDatabase db,
  String sql, [
  List<Object?> args = const [],
]) {
  final q = useQuery(db, sql, args);
  return useComputed(() => q.value.singleOrNull);
}
