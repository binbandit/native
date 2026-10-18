# Celebrations catalogue and plugin proposal

Native should offer a Celebrations plugin with an international catalogue of independently selectable
events. People choose the traditions they celebrate, the calendar they follow, and which surfaces change.
Installing the plugin should open that choice, with every event initially off. Preserve an existing
Halloween opt-in when migrating.

Research date: 18 October 2026. Halloween and Día de Muertos are confirmed requests. The wider catalogue,
display windows and plugin design below are recommendations.

Status: the contribution contract (`iconSets`, `celebrations` in [plugins](plugins.md)), the occurrence
engine and overlap policy (`Packages/AppAppearance`), the chooser (Settings ▸ Celebrations) and the first
two editions ship in the built-in Celebrations plugin (`native/Celebrations/`). Día de Muertos changes
Home only until its icons exist ([artwork hand-off](celebrations-artwork.md)); the rest of the catalogue is
listed as forthcoming, and calendars other than fixed civil dates await their resolvers.

## Confirmed editions

**Halloween:** retain the agreed automatic availability window of **1 October through 7 November
inclusive**, using local Gregorian dates. The observance itself is 31 October. Keep the developed ghost
interpretation of Native's linked mark and the four Regular, Beta, Nightly and Dev identities.
[Halloween date](https://americanenglish.state.gov/files/ae/resource_files/halloween.pdf).

**Día de Muertos:** create a separate Mexican celebration edition. Its central dates are **1 and 2
November**, with local traditions extending around them. Oaxaca's government describes cempasúchil,
candles, papel picado and family offerings, with different customs across its regions. These provide a
strong visual direction: sculpted marigold forms, warm candlelight and intricate paper edges around the
Native interlock. The edition should convey remembrance and affection. The Smithsonian describes its
personal significance through family altars and remembering loved ones.
[Oaxaca traditions](https://www.oaxaca.gob.mx/comunicacion/tradiciones-y-colores-del-dia-de-muertos-en-oaxaca/),
[Smithsonian account](https://www.americanhistory.si.edu/explore/stories/day-dead-smithsonian-its-not-halloween).

Start Día de Muertos automatic display on its two central dates. Offer an optional extended window, such
as 28 October through 3 November, labelled as a decorative preference. That wider window is a proposed
product choice, not a universal observance rule.

## Recommended catalogue

These are the first-party catalogue targets. Each named tradition should be individually selectable,
including when several entries share a date or reusable artwork. The date column describes the
celebration; it does not prescribe a longer period of decoration. Visual directions are proposals.

### New year and cultural celebrations

| Celebration | Calendar and scope | Proposed visual direction |
| --- | --- | --- |
| Gregorian New Year | 31 December evening and 1 January; distinguish the eve from the day. [Civil holiday calendar](https://www.opm.gov/policy-data-oversight/pay-leave/federal-holidays/). | Midnight graphite, champagne metal and restrained fireworks. |
| Valentine's Day | 14 February. [Library of Congress](https://blogs.loc.gov/manuscripts/2024/01/show-frederick-douglass-some-love-transcribe-his-letters-for-douglass-day-on-february-14/). | Deep carmine, rose glass and the two linked forms. |
| St Patrick's Day | 17 March; a city's festival can have a wider schedule. [Dublin festival](https://stpatricksfestival.ie/your-visit/). | Emerald enamel, gold edge light and a botanical texture. |
| Halloween | 31 October; Native's agreed display window is 1 October to 7 November. See confirmed editions. | Developed ghost links, with conspicuous Nightly stars. |
| Día de Muertos | 1–2 November, with regional traditions around those dates. See confirmed editions. | Marigolds, paper craft, candlelight and a distinct warm palette. |
| Chinese New Year / Spring Festival | First day of the first month of the Chinese calendar. [UNESCO](https://ich.unesco.org/en/RL/spring-festival-social-practices-of-the-chinese-people-in-celebration-of-traditional-new-year-02126). | Vermilion lacquer, gold and original paper or blossom details. |
| Seollal | Korean lunar new year, selected separately from Spring Festival. [Korean heritage account](https://www.korea.net/NewsFocus/policies/view?articleId=244035). | Silk texture, a restrained multicolour ribbon and soft pearlescence. |
| Tết Nguyên Đán | Vietnamese lunar new year, using the Vietnamese calendar and annual dates. [Vietnam Tourism](https://vietnam.travel/things-to-do/tet-vietnam-lunar-new-year). | Apricot or peach blossom forms, red lacquer and warm gold. |
| Lantern Festival / Yuánxiāo | Fifteenth day of the first Chinese lunar month. [Hong Kong Tourism Board](https://www.discoverhongkong.com/eng/culture/the-ultimate-guide-to-chinese-new-year-in-hong-kong.html). | Lantern light glowing through the interlock. |
| Mid-Autumn Festival | Fifteenth day of the eighth lunar month; offer the Chinese tradition as a named selection. [Hong Kong Tourism Board](https://www.discoverhongkong.com/eng/events/mid-autumn-festival.html). | An oversized luminous moon, amber and deep blue. |
| Tết Trung Thu | Vietnamese Mid-Autumn celebration, with its own name and artwork. [Vietnam Tourism](https://vietnam.travel/things-to-do/festival-event/mid-autumn-festival-0). | Star lantern structure and playful warm light. |
| Chuseok | Fifteenth day of the eighth Korean lunar month. [Korean heritage account](https://www.korea.net/NewsFocus/policies/view?articleId=244035). | Harvest gold, moonlight and a flowing ribbon. |
| Nowruz / Newroz / Navruz | Regional names and calendar practices need explicit variants. The new year is associated with the March equinox; the UN observance is 21 March. [United Nations](https://www.un.org/en/observances/international-nowruz-day). | Fresh growth, hyacinth and jewel colours. |
| Songkran | Traditional Thai new year in mid-April; keep its identity distinct from other regional new years. [UNESCO](https://ich.unesco.org/en/RL/songkran-in-thailand-traditional-thai-new-year-festival-01719). | Clear water, reflective silver and flower accents. |
| Matariki | Māori new year. Use the published Matariki calendar; the New Zealand public holiday has official annual dates through 2052. Do not equate that single holiday with every community's entire observance. [Ministry for Culture and Heritage](https://www.mch.govt.nz/engagement-maori/matariki), [official dates](https://www.beehive.govt.nz/release/matariki-holiday-dates-next-thirty-years-announced). | A carefully researched star grouping and a rich night sky, with community review of the artwork. |
| Kwanzaa | 26 December through 1 January, an African American and Pan-African cultural celebration. [Smithsonian](https://nmaahc.si.edu/explore/moments/kwanzaa). | Red, black and green, warm candlelight and a crafted surface. |
| Pride | Offer June Pride season and separate local event schedules. June cannot stand in for every city's festival: Sydney's 2027 parade is on 6 March. [Library of Congress](https://www.loc.gov/lgbt-pride-month/about/), [Sydney organiser](https://www.mardigras.org.au/ways-to-contribute/apply-to-perform/2027-parade-applications/). | Saturated spectral colour with enough structure to retain the interlock. |
| Carnival / Mardi Gras | Separate local editions and organiser schedules. New Orleans Mardi Gras falls 47 days before Western Easter; its season begins on 6 January. [New Orleans guide](https://www.neworleans.com/events/holidays-seasonal/mardi-gras/the-ultimate-mardi-gras-guide/). | Iridescent fabric, beads and dramatic colour; each community gets its own palette. |

### Religious festivals

These selections belong alongside cultural celebrations in the catalogue. A religious label should help
discovery without assuming that everyone in a tradition celebrates the same events or follows the same
calendar. The initial artwork should be reviewed by people familiar with the named tradition.

| Celebration | Calendar and scope | Proposed visual direction |
| --- | --- | --- |
| Christmas | 25 December in the selected church calendar. Offer Gregorian and Julian variants; some Orthodox churches use 25 December Gregorian, so a single “Orthodox Christmas” date would be misleading. [Church of England calendar](https://www.churchofengland.org/prayer-and-worship/worship-texts-and-resources/common-worship/churchs-year/calendar), [Orthodox Church in America explanation](https://www.oca.org/cdn/PDFs/2023-0609-EOCB.pdf). | Evergreen, garnet and warm metal, with optional winter styling independent of the holiday. |
| Easter | Western Easter date, resolved from the church calendar or a verified computus. [Church of England](https://www.churchofengland.org/prayer-and-worship/worship-texts-and-resources/common-worship/churchs-year/calendar). | Pearl, soft gold and luminous colour. |
| Orthodox Pascha | Separate Paschal calendar, even in years when its date matches Western Easter. [Greek Orthodox Archdiocese table](https://prod.goarch.org/web/greek-orthodox-archdiocese-of-america/chapel/paschalion). | Deep red, gold and candlelit depth. |
| Holi | Moving regional dates, normally in February or March; include the relevant eve when selected. [Hindu American Foundation overview](https://www.hinduamerican.org/learn/hinduism-faq). | Rich layers of coloured pigment on the linked forms. |
| Diwali / Deepavali | A festival spanning several days, with regional calendar differences. Names can be aliases while date traditions remain selectable. [Hindu American Foundation](https://www.hinduamerican.org/community/hindu-holidays-guide). | Rows of warm lights, sculpted lamp glow and jewel tones. |
| Vaisakhi | Use a named Sikh annual calendar and retain its own identity. [Sikh Coalition celebrations](https://www.sikhcoalition.org/get-involved/resources-for-educators/elementary-school-resources/). | Saffron, harvest gold and celebratory fabric. |
| Bandi Chhor Divas | Separate Sikh selection, even when its dates coincide with Diwali. Use the chosen annual calendar. [Sikh Coalition](https://www.sikhcoalition.org/resources/sikh-celebrations-lessons-activities-inclusive-classrooms/). | Warm illumination and a distinct gold and blue treatment. |
| Guru Nanak's Gurpurab | Resolve from a named annual calendar rather than a fixed Gregorian birthday. [Sikh Coalition](https://www.sikhcoalition.org/get-involved/resources-for-educators/elementary-school-resources/). | Calm radiant light and crafted gold detail. |
| Eid al-Fitr | Begins with Shawwal after Ramadan. Choose a calendar or published regional dates; moon sighting can affect the day. [Islamic Relief](https://www.islamic-relief.org.uk/giving/islamic-giving/ramadan/eid-al-fitr/). | Luminous geometric detail, midnight blue and gold. |
| Eid al-Adha | Begins on 10 Dhul Hijjah; include a configurable multiday display period. [Islamic Relief](https://www.islamic-relief.org.uk/giving/islamic-giving/qurbani/what-is-eid-qurbani/). | A distinct warm metallic and geometric edition. |
| Hanukkah / Chanukah | Eight days on the Hebrew calendar, beginning on the preceding civil evening. [Chabad annual calendar](https://www.chabad.org/holidays/default_cdo/year/2026/jewish/holidays-2026.htm). | Cobalt, silver and warm lights, with correct candle details if depicted. |
| Vesak | Full-moon observance with country and tradition variants; the UN describes a May full moon. [United Nations](https://www.un.org/en/events/vesakday/index.shtml). | Lotus-inspired structure, soft gold and quiet illumination. |
| Meskel | Ethiopian celebration of the finding of the True Cross, including its eve. Use an annual Ethiopic calendar for exact boundaries. [UNESCO](https://ich.unesco.org/en/RL/commemoration-feast-of-the-finding-of-the-true-holy-cross-of-christ-00858). | Golden flowers and bonfire light. |
| Timkat | Ethiopian Epiphany, with its own eve and procession period. Use an annual Ethiopic calendar. [UNESCO](https://ich.unesco.org/en/RL/ethiopian-epiphany-01491). | Reflective water, white textile and jewel colour. |

### Community and playful editions

These should be additional choices within the same plugin. They are useful ways to celebrate without
requiring a religious or national preference.

| Celebration | Calendar and scope | Proposed visual direction |
| --- | --- | --- |
| Earth Day | 22 April. [United Nations](https://www.un.org/en/observances/earth-day/background). | Deep green, living texture and a blue atmospheric edge. |
| Juneteenth | 19 June. [Smithsonian educational resource](https://nmaahc.si.edu/sites/default/files/2021-12/nmaahc_kids_juneteenth_resource.pdf). | Red, blue and a radiant freedom motif developed with community input. |
| Thanksgiving in Canada | Its own Canadian schedule; use published annual dates. [Canadian government](https://www.canada.ca/en/revenue-agency/services/tax/public-holidays.html). | Warm harvest materials and autumn colour. |
| Thanksgiving in the United States | Separate US schedule and preference. [US government calendar](https://www.opm.gov/policy-data-oversight/pay-leave/federal-holidays/). | A distinct harvest edition with a restrained material treatment. |
| Pi Day / International Day of Mathematics | 14 March. [UNESCO mathematics day](https://www.unesco.org/en/days/mathematics). | Engraved mathematical curves and small precise highlights. |
| Programmers' Day | Day 256 of the year, which means 12 September in leap years and 13 September otherwise. [JetBrains account](https://blog.jetbrains.com/blog/2018/09/18/celebrating-the-drive-to-develop-on-programmers-day-2018/). | Terminal phosphor and an original circuit or code texture. |
| Ada Lovelace Day | Second Tuesday in October. [Event organiser](https://findingada.com/about/when-is-ald/). | Brass, ink and an original punched-card texture. |
| Personal celebrations | User-entered birthdays, anniversaries and custom annual dates. Let the person choose the name, duration and leap-day handling. | A small set of polished confetti, ribbon, metallic and colour editions. |

## Expansion packs

The plugin format should support these groups without another app release. This is the next catalogue
wave after the initial artwork and date engine, with each event still selectable separately.

| Pack | Events to support | Calendar and editorial requirements |
| --- | --- | --- |
| Jewish festivals | Purim, Passover, Shavuot, Rosh Hashanah, Sukkot, Shemini Atzeret and Simchat Torah. | Hebrew dates, evening boundaries and Israel or diaspora variants. Keep the relevant neighbouring festivals distinct. [Annual calendar](https://www.chabad.org/holidays/default_cdo/year/2026/jewish/holidays-2026.htm). |
| South Asian festivals | Lohri, Makar Sankranti, Pongal, Ugadi, Gudi Padwa, Onam, Raksha Bandhan, Janmashtami, Ganesh Chaturthi, Sharad Navaratri, Durga Puja and Dussehra. | Separate regional selections and solar or lunisolar rules. Do not treat overlapping festivals as interchangeable names. [Dharmic calendar](https://www.hinduamerican.org/wp-content/uploads/2025/12/1.26_000.01-2026-Dharmic-Calendar.pdf), [festival overview](https://www.hinduamerican.org/learn/hinduism-faq). |
| Sikh and Jain festivals | Guru Gobind Singh's Gurpurab and Mahavir Jayanti, alongside the initial Sikh selections. | Annual community calendars and distinct descriptions. [Sikh Coalition](https://www.sikhcoalition.org/get-involved/resources-for-educators/elementary-school-resources/), [Dharmic calendar](https://www.hinduamerican.org/wp-content/uploads/2025/12/1.26_000.01-2026-Dharmic-Calendar.pdf). |
| Bahá’í celebrations | Naw-Rúz, Ridván and the Twin Holy Birthdays. | Current Badí’ calendar, sunset boundaries and published annual dates. The Twin Birthdays use a lunar rule; fixed old Gregorian birthdays would be wrong. [Official Bahá’í calendar](https://www.bahai.org/action/devotional-life/calendar), [calendar clarification](https://www.bahai.org/library/authoritative-texts/the-universal-house-of-justice/messages/20140710_001/1). |
| Japanese celebrations | Shōgatsu, Tanabata and Obon. | Regional July or August schedules must be selectable. A city's Tanabata dates should not become a universal date for Japan. [Japan holiday guide](https://www.japan.travel/en/plan/business-hours-and-holidays/), [Tanabata example](https://www.japan.travel/en/spot/423/), [Obon guide](https://www.japan.travel/en/guide/august/). |
| Korean seasonal traditions | Daeboreum, Dano and Dongji, alongside Seollal and Chuseok. | Lunar dates and solar terms require different rules. [Korean heritage account](https://www.korea.net/NewsFocus/policies/view?articleId=244035). |
| Further Chinese festivals | Dragon Boat Festival, Cheung Chau Bun Festival and local temple festivals; offer Yu Lan with a remembrance treatment. | Chinese lunar dates and local schedules. Dragon Boat falls on the fifth day of the fifth lunar month; distinguish a racing event's schedule from the festival date. [Hong Kong Tourism Board](https://www.discoverhongkong.com/eng/culture/celebrate-with-these-time-honoured-chinese-festivities.html). |
| Tibetan new year | Losar, with the named Tibetan calendar and a separate community identity. | Resolve its own annual dates instead of copying another lunar new year. [Dalai Lama's Losar greetings](https://www.dalailama.com/videos/tibetan-new-years-greetings). |
| Ethiopian cultural festivals | Enkutatash and Irreecha, alongside Meskel and Timkat in the initial catalogue. | Use the relevant calendar and annual local schedules. Preserve their separate cultural and religious meanings. [Ethiopian Ministry of Tourism calendar](https://visitethiopia.et/). |
| Thai and Lanna light festivals | Loi Krathong and Yi Peng as separate selectable traditions. | Source annual local schedules and distinguish floating offerings from hanging or sky lanterns. [Tourism Authority of Thailand](https://www.tourismthailand.org/Articles/loi-krathong-2025-all-area-en), [Yi Peng example](https://www.tourismthailand.org/Articles/hundred-thousand-lantern-en). |
| Local festivals and Pride | City Pride festivals and regional Carnival editions, with community-contributed celebrations. | Source each schedule from its organiser, keep the year and place explicit, and use original artwork. Sydney demonstrates why June and Easter-based rules cannot cover everything called Mardi Gras. [Sydney organiser](https://www.mardigras.org.au/2027-festival/), [New Orleans guide](https://www.neworleans.com/events/holidays-seasonal/mardi-gras/the-ultimate-mardi-gras-guide/). |
| National and regional days | Independence, national, civic and regional celebrations chosen by the user. | Publish separate country or regional packs backed by their official calendars. Each entry must distinguish the celebration date from a substitute public day off. |
| Seasons and astronomy | Equinox and solstice editions, plus user-chosen summer, autumn, winter and spring themes. | Use astronomical dates and a chosen hemisphere. Keep these preferences separate from Christmas and other festivals. |

Ramadan should be available as a **quiet observance** in a subsequent observances pack, independently of
both Eids. The calendar must follow the user's selected authority or regional dates. Moon sighting can
vary by place. [Islamic Relief calendar guidance](https://www.islamic-relief.org.uk/resources/islamic-calendar/sighting-the-crescent-moon/).
The same pack can later support solemn days such as Yom Kippur and Good Friday with suitable restrained
artwork. They should not inherit a generic party treatment.

Additional local and religious traditions can enter through community packs after their calendar and
artwork receive review. This catalogue is a deliberate first-party scope, not an exhaustive list of the
world's observances. A complete public-holiday database is a different product from crafted celebration
editions.

## Choosing celebrations

Keep the catalogue, descriptions and previews available throughout the year. Gate automatic application
by date so someone can choose Halloween in February for the coming October. This replaces the current
seasonal hiding of the setting while retaining the agreed Halloween activation window.

Each selection needs:

- A preview for the current build, its next occurrence and the exact proposed display window.
- An independent **Celebrate automatically** switch and calendar or regional variant where relevant.
- Separate **App icon** and **Home appearance** choices. A selected custom icon remains the base to
  restore after a celebration ends.
- A choice between the core observance and a clearly labelled extended decorative window.
- A temporary **Skip this occurrence** action and an immediate way to restore the base appearance.

Packs help people browse; installing or enabling a pack must not turn on every celebration it contains.

The chooser offers two shortcuts, both explicit and both undoable (⌘Z). **Turn All On** and **Turn
All Off** change every celebration at once, keeping each one's style, surfaces and window; turning
them all on downloads nothing immediately, since each icon pack arrives a week before its dates.
**Turn On a Country's Holidays** turns on, in one step, the catalogue's celebrations that are official
public holidays in a country the user picks, so someone in the United States can get Thanksgiving and
Juneteenth without hunting for them. It is opt-in by design: the Mac's region only puts that country
at the top of the list as "Your region", and nothing is enabled until the person picks a country. A
country's list comes from its government's published public-holiday calendar (statutory, nationwide
days off, cited per country), never from a judgement of what is "widely celebrated" there, so the
shortcut states a fact about a calendar rather than inferring anyone's religion or culture.
Search should recognise common English names, local names and spelling variants. Locale may format
dates and language, but must not infer someone's religion, ethnicity or celebrations. No location access
is needed for browsing or ordinary civil-date themes.

## Overlapping events

Use a deterministic selection policy and show why the active edition was chosen:

1. An explicit temporary choice or skip takes effect first.
2. An event on its core observance dates outranks another event's extended decorative window.
3. When core dates overlap, use the person's chosen event order. Show a choice when first enabling
   overlapping events, with a stable catalogue order as the fallback until changed.
4. When no enabled event applies, restore the person's base icon and appearance.

For the confirmed example, a person enabling both events gets Halloween through 31 October,
Día de Muertos on 1–2 November, then Halloween again on 3–7 November. On 8 November the base returns.
They can change that priority or skip the switch. Do not blend the two editions automatically.

## Calendar requirements

Keep an event's **observance** separate from its **decorative window**. A public holiday, a religious
festival, the preceding evening and a tourist event can have different boundaries. Preserve the source
and meaning of each date instead of turning the entire public closure into the festival.

| Date kind | Required behaviour |
| --- | --- |
| Fixed civil dates | Local calendar dates; support windows crossing December and January. |
| Weekday or ordinal rules | Nth weekday for Ada Lovelace Day and day 256 for Programmers' Day; handle leap years. |
| Christian calendars | Distinct Western Easter and Orthodox Pascha resolvers; Christmas uses the selected calendar. Use ecclesiastical calculations or verified tables, rather than an arbitrary astronomical full moon. |
| Lunisolar calendars | Named Chinese, Vietnamese, Korean and regional South Asian rules, including leap months where relevant. A generic “lunar” calendar is insufficient. |
| Hebrew calendar | Leap months, civil evening starts, festival lengths and Israel or diaspora variants. |
| Islamic calendars | Named authority or region, published dates and a visible provisional status when dates await confirmation. Allow a small manual date correction. |
| Badí’ and Ethiopic calendars | Named calendar support or verified annual tables, with the applicable eve and year conversion. |
| Astronomy and published schedules | Versioned annual tables for dates such as Matariki and city festivals; retain the source and coverage years. |
| Sunset or nightfall boundaries | Store the boundary type explicitly. Offer civil-date decoration as a labelled alternative. Exact astronomical boundaries require a user-chosen place or suitable local timetable; a time zone alone cannot determine sunset. |

Return a list of occurrences for a queried interval. Do not assume an event occurs exactly once in a
Gregorian year. Build display ranges from calendar days, never multiples of 86,400 seconds. Recompute
after time-zone changes, clock changes, wake and activation, and schedule the next actual boundary.

Ship enough verified future dates for offline use. If a table expires or a date cannot be resolved,
preserve the base appearance and explain the missing date in the catalogue. Updating calendar data must
not change the user's event selections or silently switch their chosen tradition.

## Artwork requirements

Every shipped edition needs a coherent **Regular, Beta, Nightly and Dev** family. The Native linked
shape remains recognisable at Dock sizes. Nightly keeps large, high-contrast stars; seasonal details
must not cover them. Beta and Dev retain their established channel cues, including Dev's code or
blueprint character. A celebration changes materials, colour and supporting details within that family.

Create proper light and dark versions and review small-size contrast. Where Native uses compiled
Icon Composer assets, retain system Default, Dark, Clear and Tinted appearances. Clear is a system
appearance, not an extra celebration or manually selectable theme. Do not force snowy imagery for
Christmas or invert astronomical seasons for southern-hemisphere users.

The current Mac seasonal override uses `NSApplication.applicationIconImage` with light or dark images.
Those images do not carry the compiled icon's layered Clear and Tinted renditions. The plugin proposal
does not solve this platform limitation. Validate a supported native appearance path before promising
Composer-quality system rendering for dynamically loaded icon packs. Home styling and icon styling
must degrade independently when a platform cannot apply an icon.

Use original assets. Research photographs, another product's icon, festival logos and franchise imagery
are references, not assets to copy into the app. Cultural review should check the event's meaning,
names, symbols and details before artwork ships. Motion and sound are separate explicit preferences;
respect Reduce Motion and never obscure task content or approvals with decoration.

## Plugin integration proposal

The current [plugin contract](plugins.md) supports agents, MCP servers and workflows. Celebrations need
a new contribution type; adding an unrecognised field to today's manifest will not install a theme.

Use declarative celebration contributions in the existing plugin system. Put pure date resolution,
occurrence selection, overlap rules and preference migration in `Packages/AppAppearance`. Keep feature
coordination in a dedicated `native/Celebrations/` folder, platform icon application behind
`native/Platform/`, and reusable visual tokens and marks in the design system. UI actions go through
model methods. One resolved active celebration should drive both the icon and Home appearance.

Each event contribution should declare:

| Field group | Information |
| --- | --- |
| Identity | Stable namespaced ID, localised title, aliases, description and discovery tags. Regional variants have stable IDs of their own. |
| Provenance | Source URLs, publisher, calendar authority, data version, last review and covered years. |
| Calendar | Rule or annual occurrences, named tradition or region, core start and end, boundary type and provisional status. |
| Display | Default decorative window, available duration choices, quiet or festive treatment and supported surfaces. |
| Artwork | Assets by build channel and supported appearance, plus palette and Home contributions. Paths stay inside the plugin's directory. |
| Compatibility | Manifest version, minimum app support and a useful fallback when an appearance or platform is unsupported. |

Keep user preferences outside plugin manifests: enabled event IDs, selected calendar, surface choices,
duration, priority, manual date adjustment and per-occurrence skips. Removing or disabling a plugin
restores the base appearance immediately and cancels its pending boundary work. Reload should validate
contributions individually so one broken calendar or asset does not disable unrelated plugins.

Migrate the existing Halloween boolean into its stable event ID. Reuse the current build-channel
resolution and agreed 1 October–7 November rule. Replace holiday-specific branches with the shared
active occurrence rather than adding another boolean and timer for every festival.

## Delivery order and acceptance

First establish the contribution contract, occurrence engine and chooser using Halloween and
Día de Muertos. Their November overlap exercises the policy using confirmed requirements. Then create
the international catalogue in reviewed artwork batches, followed by the expansion packs. Keep each
unfinished edition unavailable for automatic application until its calendar and four build variants
are complete; its catalogue preview can state that artwork is forthcoming.

Before shipping the engine, cover the following with package tests and isolated app verification:

- Halloween's opening and closing boundaries, Día de Muertos overlap, skip, priority and base restoration.
- Cross-year Kwanzaa and New Year windows, leap days, weekday rules and multiple occurrences in one year.
- Daylight-saving transitions, travel across time zones, sleep across a boundary and manual clock changes.
- Western Easter and Pascha matching and differing years; Hebrew leap years and regional festival lengths.
- Confirmed versus provisional lunar dates, a manual correction and an expired annual table.
- Plugin disable, removal, malformed contributions, missing channel artwork and offline launch.
- Relaunch persistence, light and dark, system icon appearances, Reduce Motion, keyboard and touch access.

Calendar fixtures should come from the cited annual calendars and retain their source and year. An icon
preview proves artwork availability; the running app must separately prove activation, restoration and
the actual platform appearance behaviour.
