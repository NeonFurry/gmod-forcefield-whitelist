# gmod-forcefield-whitelist

[![License](https://img.shields.io/badge/License-Boost_1.0-blue.svg)](https://www.boost.org/LICENSE_1_0.txt)
[![Garry's Mod](https://img.shields.io/badge/Game-Garry%27s%20Mod-orange)](https://store.steampowered.com/app/4000/)

Аддон для Garry's Mod: расширенный вайтлист (белый список) для силовых полей — **игроки, команды, редакторы и NPC-классы**.

Расширение для мода **Bendable Combine Forcefield** от **bol_snaphak**.
Оригинальный мод: https://steamcommunity.com/sharedfiles/filedetails/?id=3824144302
*(страница мода на момент публикации была удалена из Workshop — оригинальные файлы прилагаются в репозитории в папке `forcefield_original`)*

---

## Что делает

Оригинальный мод позволяет добавить в вайтлист поля только **команды** (Teams Ignored by the Field). Этот аддон добавляет:

- **вайтлист игроков** — поимённо, конкретные игроки;
- **вайтлист команд** — через родной механизм мода (кнопки меню вызывают `AddTeamToWhitelist` / `RemoveTeamFromWhitelist` самого поля, так что списки синхронизированы со штатным пунктом C-меню);
- **вайтлист редакторов** — «кто редактирует — тот проходит»;
- **вайтлист NPC-классов** — вписываешь класс, например `npc_vj_automaton_trooper`, и проходят **все** NPC этого типа (не один конкретный бот);
- **меню управления полем** без всяких ALT-комбинаций: клавиша **E** на поле, пункт **Forcefield Menu** в контекстном меню (C → ПКМ), консольная команда `ffwl_menu`, чат-команда `!ffmenu`.

## Почему это работает стабильно (коротко о главном)

У оригинального мода собственный хук коллизий:

```lua
hook.Add("ShouldCollide", "Forcefield_ShouldCollide", ...)
```

который вызывает метод `ENT:ShouldCollideWith(ent)`. В GMod хук-цепочка `ShouldCollide` обрывается на первом хуке, вернувшем ответ, а порядок вызова хуков **не гарантирован**. Аддон, добавляющий второй хук с тем же именем, даёт непредсказуемый результат: вайтлист «то работает, то нет».

Поэтому здесь **своих хуков коллизий нет вообще**: аддон оборачивает родной метод `ShouldCollideWith` самого поля. Проверка вайтлиста выполняется первой, и только если никто не пропущен — отдаётся оригинальная логика мода (штатный вайтлист команд, типы поля, блок пропов). Конфликтов по порядку хуков не существует в принципе.

## Как работает проход NPC

- Проверка **персональная для каждого NPC**: поле сверяет класс конкретного NPC у стены со списком конкретного поля. Толпа чужих NPC у стены остаётся запертой — проход открывается только тем, чей класс вписан.
- Пока вписанный NPC находится в узкой зоне (~170 юнитов) у поля, ему временно меняется группа коллизий; при отходе дальше 250 юнитов группа возвращается. За пределами зоны всё как обычно.
- Вписанный NPC **не может «открыть дверь» другим** — разрешение не передаётся.

## Установка

1. Убедись, что оригинальный мод (Bendable Combine Forcefield) установлен.
2. Скопируй папку `forcefield_whitelist` в `garrysmod/addons/`.
3. Полностью перезапусти GMod.
4. При загрузке в консоли должна появиться строка `[FFWL] Адаптация под prop_forcefield_field загружена`.

## Использование

1. Заспавни поле через спавн-меню (категория **Fun + Games**). Спавнятся два эмиттера и само поле между ними.
2. Наведись на стену поля — появится подсказка «E — меню вайтлиста поля».
3. Нажми **E** — откроется Forcefield Manager.

### Кнопки меню

| Кнопка | Действие |
|---|---|
| Add Player | Добавить игрока в вайтлист |
| Remove Player | Убрать игрока из вайтлиста |
| Add Team | Добавить команду (через родной механизм мода) |
| Remove Team | Убрать команду |
| Toggle Editors | Вкл/выкл допуск редакторов |
| Add NPC Class | Вписать класс NPC (например, `npc_vj_automaton_trooper`) |
| Remove NPC Class | Убрать класс NPC |
| Close | Закрыть меню |

### Консольные команды

| Команда | Что делает | Права |
|---|---|---|
| `ffwl_menu` | Открыть меню вайтлиста | админ или ULX-флаг `forcefield_edit` |
| `ffwl_scan` | Напечатать классы всех полей на карте | админ или ULX-флаг `forcefield_edit` |
| `ffwl_debug` | Полное состояние поля: коллизия, владелец, все списки, твои права | админ или ULX-флаг `forcefield_edit` |

### Чат-команды

- `!ffmenu` — открыть меню вайтлиста.

### Права доступа

- По умолчанию меню доступно **админам**.
- С установленным ULX можно выдавать отдельный флаг **`forcefield_edit`** (XGUI → Groups → флаги): игрок с флагом получает доступ к меню и диагностике без полного админа.
- Без ULib проверка сводится к стандартному `IsAdmin`.

## Структура

```
forcefield_whitelist/
├── addon.json
├── README.md
└── lua/
    └── autorun/
        └── zz_ffwl_menu.lua    — весь аддон, один файл
```

`zz_` в начале имени файла — чтобы autorun загрузил аддон после всех сущностей мода.

## Известные ограничения

- Вайтлист хранится **на сущности поля**: после пересоздания поля или смены карты список пуст — заполнить заново. (Сохранение между сессиями планируется.)
- При типе поля **2** пули не летят сквозь поле даже для вайтлистных: мод блокирует трейсы, не зная, кто стрелял.
- Проход NPC работает по **классу**, а не по конкретной особи: вписанный класс пропускает всех NPC этого типа.
- Пока вписанный NPC находится в зоне прохода, он может слегка «проталкиваться» сквозь стоящих вплотную игроков и пропы — побочный эффект смены группы коллизий. За пределами зоны всё стандартно.
- Проход NPC настроен на тип поля **0** (блок NPC). На других типах поля (блок пропов / блок пуль) NPC-логика может срабатывать не к месту.

## Благодарности

- **bol_snaphak** — автор оригинального мода Bendable Combine Forcefield. Код мода написан читаемо и легко расширяется, что и позволило сделать эту адаптацию.
- Код адаптации распространяется под той же лицензией Boost Software License 1.0.

## Лицензия

Boost Software License 1.0 (SPDX: `BSL-1.0`)

```
Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant and this restriction, must be included in all copies
or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```
