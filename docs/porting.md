# Перенос правок на новую сборку Sikarugir

Смещения привязаны к конкретным бинарникам. После обновления движка `ow-patch.sh` сообщит «unsupported engine build» и ничего не тронет.

## 0. Проверить, нужна ли правка вообще
- `gsbase-loop` не нужна, если движок основан на Wine ≥ 11.4 (там upstream-коммит 6f6f66ee).
- Если в новой сборке исправили мышь в исходниках, часть правок может оказаться лишней — проверять по поведению.

## 1. Завести каталог сборки
```bash
B=builds/<имя движка>
mkdir -p "$B"
LIB="/path/Wrapper.app/Contents/SharedSupport/wine/lib/wine/x86_64-unix"
printf 'ntdll.so\t%s\nwinemac.so\t%s\n' "$(shasum -a 256 "$LIB/ntdll.so" | cut -d' ' -f1)" \
    "$(shasum -a 256 "$LIB/winemac.so" | cut -d' ' -f1)" > "$B/originals.tsv"
```
Хэши снимать с **непропатченных** файлов.

## 2. Найти места заново
Не переносить смещения — искать функции:
- **Методы Objective-C** (`handleMouseMove:`, `setCursorPosition:`, `stopClippingCursor`): `otool -oV winemac.so` даёт таблицу методов с IMP;
  селекторы в `__objc_selrefs` — chained fixups, младшие 36 бит указателя = адрес строки имени.
- **Поля (ivars)**: `otool -oV` печатает смещения (`clientWantsCursorHidden`, `lastSetCursorPositionTime`, `clipCursorHandler`).
- **`macdrv_clip_cursor`**: по вызову заглушки `NSContainsRect` (найти GOT-слот через `llvm-objdump --macho --bind`, затем заглушку `jmpq *slot`).
- **`macdrv_mouse_button`**: по ссылке на таблицу флагов кнопок (`03 80 00 00 09 80 00 00 21 80 00 00` = LEFTDOWN/RIGHTDOWN/MIDDLEDOWN с ABSOLUTE|MOVE).
- **Прокрутка**: по константам `0x8801` и `0x9001` (WHEEL/HWHEEL | ABSOLUTE | MOVE).
- **`macdrv_GetCursorPos`**: по строке трассы `pointer at (%g,%g) server pos %d,%d`.
- Пещеры — только в выравнивающих `nop` между функциями; в этой сборке самые длинные ~10–15 байт.

Дизассемблер: `xcrun llvm-objdump --disassemble --start-address=… --stop-address=… winemac.so`.

## 3. Записать правки и проверить
Добавить строки в `builds/<сборка>/patches.tsv` (оригинальные байты обязательны — скрипт сверяет их перед записью), затем:
```bash
./ow-patch.sh status /path/Wrapper.app
./ow-patch.sh apply  /path/Wrapper.app
```

## 4. Как проверять поведение
В `Info.plist` обёртки временно выставить `WINEDEBUG=+timestamp,+pid,+tid,+rawinput,+cursor,+loaddll` и читать
`Contents/SharedSupport/Logs/LastRunWine.log` (в нём двоичные байты: `LC_ALL=C grep -a`). Лог дописывается на ходу — анализировать копию.
- в бою не должно быть `mouse_moved … absolute`, первое событие после включения захвата — маленькое;
- в меню `pointer` и `server pos` в `macdrv_GetCursorPos` совпадают;
- рывок камеры надёжнее всего ловить записью экрана с меткой (Esc открывает меню — видно и на видео, и в логе как смену режима).
