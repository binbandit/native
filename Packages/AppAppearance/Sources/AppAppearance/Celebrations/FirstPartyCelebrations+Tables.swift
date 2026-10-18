// Generated from the sourced research in docs/celebrations.md (18 October 2026). Each table cites
// its sources; years resting on an almanac alone (Drik Panchang) are to be rechecked when the
// authorities publish. Regenerate rather than editing dates by hand.

extension FirstPartyCelebrations {
    /// Published dates for calendars Native doesn't compute, by edition.
    static let publishedDates: [String: PublishedDates] = [
        "spring-festival": PublishedDates(
            tradition: "Chinese lunisolar calendar (UTC+8), 1st day of the 1st month",
            authority: "Hong Kong Observatory",
            sources: ["https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2026e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2027e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2028e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2029e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2030e.pdf"],
            note: "Read from the first day of the '1st Lunar Month' in each year's Gregorian-Lunar Calendar Conversion Table. Korean Seollal (2027, 2028) and Vietnamese Tet (2030) fall on different days because their calendars use UTC+9 and UTC+7.", isProvisional: false,
            occurrences: [("2026-02-17", "2026-02-17"), ("2027-02-06", "2027-02-06"), ("2028-01-26", "2028-01-26"), ("2029-02-13", "2029-02-13"), ("2030-02-03", "2030-02-03")]),
        "lantern-festival": PublishedDates(
            tradition: "Chinese lunisolar calendar (UTC+8), 15th day of the 1st month",
            authority: "Hong Kong Observatory",
            sources: ["https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2026e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2027e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2028e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2029e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2030e.pdf"],
            note: "Read as the Gregorian day the table marks as lunar date 15 of the 1st Lunar Month.", isProvisional: false,
            occurrences: [("2026-03-03", "2026-03-03"), ("2027-02-20", "2027-02-20"), ("2028-02-09", "2028-02-09"), ("2029-02-27", "2029-02-27"), ("2030-02-17", "2030-02-17")]),
        "mid-autumn": PublishedDates(
            tradition: "Chinese lunisolar calendar (UTC+8), 15th day of the 8th month",
            authority: "Hong Kong Observatory",
            sources: ["https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2026e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2027e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2028e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2029e.pdf", "https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2030e.pdf"],
            note: "Read as the Gregorian day the table marks as lunar date 15 of the 8th Lunar Month (the festival day itself, not any public holiday around it).", isProvisional: false,
            occurrences: [("2026-09-25", "2026-09-25"), ("2027-09-15", "2027-09-15"), ("2028-10-03", "2028-10-03"), ("2029-09-22", "2029-09-22"), ("2030-09-12", "2030-09-12")]),
        "seollal": PublishedDates(
            tradition: "Korean lunisolar calendar (UTC+9); statutory 3-day holiday: lunar 12/last, 1/1, 1/2",
            authority: "Korea Astronomy and Space Science Institute (lunar-solar conversion); Regulations on Public Holidays of Government Offices",
            sources: ["https://astro.kasi.re.kr/life/pageView/8", "https://elaw.klri.re.kr/eng_mobile/viewer.do?hseq=62747&key=5&type=part"],
            note: "Seollal itself (lunar 1/1, from KASI's converter) is the middle day: 2026-02-17, 2027-02-07, 2028-01-27, 2029-02-13, 2030-02-03. start/end is the day before through the day after, per Article 2(4) of the Presidential Decree. Substitute holidays (e.g. 2027-02-09) are excluded. 2027 and 2028 differ from Chinese New Year by one day.", isProvisional: false,
            occurrences: [("2026-02-16", "2026-02-18"), ("2027-02-06", "2027-02-08"), ("2028-01-26", "2028-01-28"), ("2029-02-12", "2029-02-14"), ("2030-02-02", "2030-02-04")]),
        "chuseok": PublishedDates(
            tradition: "Korean lunisolar calendar (UTC+9); statutory 3-day holiday: lunar 8/14-8/16",
            authority: "Korea Astronomy and Space Science Institute (lunar-solar conversion); Regulations on Public Holidays of Government Offices",
            sources: ["https://astro.kasi.re.kr/life/pageView/8", "https://elaw.klri.re.kr/eng_mobile/viewer.do?hseq=62747&key=5&type=part"],
            note: "Chuseok itself (lunar 8/15, from KASI's converter) is the middle day: 2026-09-25, 2027-09-15, 2028-10-03, 2029-09-22, 2030-09-12. start/end is the day before through the day after, per Article 2(9) of the Presidential Decree. Substitute holidays are excluded.", isProvisional: false,
            occurrences: [("2026-09-24", "2026-09-26"), ("2027-09-14", "2027-09-16"), ("2028-10-02", "2028-10-04"), ("2029-09-21", "2029-09-23"), ("2030-09-11", "2030-09-13")]),
        "tet": PublishedDates(
            tradition: "Vietnamese lunisolar calendar (UTC+7), 1st day of the 1st month (Mung 1 Tet)",
            authority: "Government of Viet Nam (2026, 2027 holiday notices); Bao Nghe An official calendar (all years)",
            sources: ["https://xaydungchinhsach.chinhphu.vn/de-xuat-phuong-an-nghi-tet-am-lich-nghi-le-quoc-khanh-nam-2026-119251002130522291.htm", "https://xaydungchinhsach.chinhphu.vn/de-xuat-2-phuong-an-nghi-tet-nguyen-dan-2027-tet-dinh-mui-11926080513033257.htm", "https://baonghean.vn/am-duong-lich-nam-2026.html", "https://baonghean.vn/am-duong-lich-nam-2027.html", "https://baonghean.vn/am-duong-lich-nam-2028.html", "https://baonghean.vn/am-duong-lich-nam-2029.html", "https://baonghean.vn/am-duong-lich-nam-2030.html"],
            note: "2026 and 2027 are confirmed by government holiday notices (16/02/2026 = 29 Chap; 10/02/2027 = mung 5 thang Gieng). 2028-2030 come only from the lunar calendar grids of Bao Nghe An, a provincial Party newspaper. 2030 is 2 February in Vietnam but 3 February in the Chinese calendar.", isProvisional: false,
            occurrences: [("2026-02-17", "2026-02-17"), ("2027-02-06", "2027-02-06"), ("2028-01-26", "2028-01-26"), ("2029-02-13", "2029-02-13"), ("2030-02-02", "2030-02-02")]),
        "tet-trung-thu": PublishedDates(
            tradition: "Vietnamese lunisolar calendar (UTC+7), 15th day of the 8th month",
            authority: "Bao Nghe An official calendar",
            sources: ["https://baonghean.vn/am-duong-lich-nam-2026.html", "https://baonghean.vn/am-duong-lich-nam-2027.html", "https://baonghean.vn/am-duong-lich-nam-2028.html", "https://baonghean.vn/am-duong-lich-nam-2029.html", "https://baonghean.vn/am-duong-lich-nam-2030.html"],
            note: "Read from the cells labelled '15/8 ... Ngay Tet Trung thu' in each year's grid. Bao Nghe An is a provincial state newspaper, not a calendar authority; no government source publishes these dates ahead. All five years match the Hong Kong Observatory's Chinese dates.", isProvisional: false,
            occurrences: [("2026-09-25", "2026-09-25"), ("2027-09-15", "2027-09-15"), ("2028-10-03", "2028-10-03"), ("2029-09-22", "2029-09-22"), ("2030-09-12", "2030-09-12")]),
        "nowruz": PublishedDates(
            tradition: "UN International Day of Nowruz (fixed 21 March)",
            authority: "United Nations",
            sources: ["https://www.un.org/en/observances/international-nowruz-day"],
            note: "The UN fixes the observance on 21 March (A/RES/64/253) and says Nowruz itself falls on the vernal equinox, 'usually March 20 or 21'. No reachable official source was found for Iran's 1 Farvardin (the Tehran-noon equinox rule puts it on 20 March in 2028 and 2029), so the Iranian civil date is not included.", isProvisional: false,
            occurrences: [("2026-03-21", "2026-03-21"), ("2027-03-21", "2027-03-21"), ("2028-03-21", "2028-03-21"), ("2029-03-21", "2029-03-21"), ("2030-03-21", "2030-03-21")]),
        "songkran": PublishedDates(
            tradition: "Thai official Songkran holidays",
            authority: "Bank of Thailand",
            sources: ["https://www.bot.or.th/content/dam/bot/fipcs/documents/FPG/2568/EngPDF/25680162.pdf", "https://www.nationthailand.com/news/general/40070369"],
            note: "2026 is from Bank of Thailand Notification No. 31/2568. The 2027 dates come from Nation Thailand's report of the Bank of Thailand's 2027 list; the notification itself could not be opened. Cabinet bridge days and substitute days are excluded. 2028-2030 have no published list yet.", isProvisional: false,
            occurrences: [("2026-04-13", "2026-04-15"), ("2027-04-13", "2027-04-15")]),
        "matariki": PublishedDates(
            tradition: "New Zealand Matariki public holiday",
            authority: "Matariki Advisory Committee, as published by Te Papa (govt.nz)",
            sources: ["https://www.tepapa.govt.nz/digital-museum/explore-digital-museum/matariki-maori-new-year/dates-for-matariki-public-holiday"],
            note: "This is the official Friday public holiday. The Tangaroa lunar period around it is different: 8-11 Jul 2026, 27-30 Jun 2027, 15-18 Jul 2028, 4-7 Jul 2029, 23-26 Jun 2030. The beehive.govt.nz release named in the spec blocks automated fetches, so it was not read.", isProvisional: false,
            occurrences: [("2026-07-10", "2026-07-10"), ("2027-06-25", "2027-06-25"), ("2028-07-14", "2028-07-14"), ("2029-07-06", "2029-07-06"), ("2030-06-21", "2030-06-21")]),
        "holi": PublishedDates(
            tradition: "Hindu lunisolar (North India): Holi / Dhulandi, the day after Holika Dahan",
            authority: "Government of India DoPT holiday lists (2026, 2027); Drik Panchang, New Delhi (2028-2030)",
            sources: ["https://www.staffnews.in/wp-content/uploads/2025/07/Holidays-to-be-observed-in-Central-Government-Offices-during-the-year-2026.pdf", "https://www.staffnews.in/wp-content/uploads/2026/07/Holiday-list-2027.pdf", "https://www.drikpanchang.com/festivals/holi/festivals-holi-rangwali.html?geoname-id=1261481&year=2028", "https://www.drikpanchang.com/festivals/holi/festivals-holi-rangwali.html?geoname-id=1261481&year=2029", "https://www.drikpanchang.com/festivals/holi/festivals-holi-rangwali.html?geoname-id=1261481&year=2030", "https://www.hinduamerican.org/wp-content/uploads/2025/12/1.26_000.01-2026-Dharmic-Calendar.pdf"],
            note: "The DoPT lists are mirrored copies of the official Office Memoranda (F.No.12/2/2023-JCA dated 3 July 2025 and 16 July 2026). Sources disagree in 2027: DoPT gives Holika Dahan on 22 March and Holi on 23 March, while Drik Panchang (New Delhi) gives 21 and 22 March. DoPT is used here. For 2026, the Hindu American Foundation's US calendar lists Holi on 3 March and DoPT and Drik list 4 March. Regional dates vary.", isProvisional: false,
            occurrences: [("2026-03-04", "2026-03-04"), ("2027-03-23", "2027-03-23"), ("2028-03-11", "2028-03-11"), ("2029-03-01", "2029-03-01"), ("2030-03-20", "2030-03-20")]),
        "diwali": PublishedDates(
            tradition: "Hindu lunisolar: Lakshmi Puja day (Kartika Amavasya), New Delhi",
            authority: "Drik Panchang (New Delhi), confirmed by Government of India DoPT (2026, 2027) and Hindu American Foundation (2026)",
            sources: ["https://www.drikpanchang.com/festivals/lakshmipuja/festivals-lakshmipuja-timings.html?geoname-id=1261481&year=2026", "https://www.drikpanchang.com/festivals/lakshmipuja/festivals-lakshmipuja-timings.html?geoname-id=1261481&year=2027", "https://www.drikpanchang.com/festivals/lakshmipuja/festivals-lakshmipuja-timings.html?geoname-id=1261481&year=2028", "https://www.drikpanchang.com/festivals/lakshmipuja/festivals-lakshmipuja-timings.html?geoname-id=1261481&year=2029", "https://www.drikpanchang.com/festivals/lakshmipuja/festivals-lakshmipuja-timings.html?geoname-id=1261481&year=2030", "https://www.staffnews.in/wp-content/uploads/2025/07/Holidays-to-be-observed-in-Central-Government-Offices-during-the-year-2026.pdf", "https://www.staffnews.in/wp-content/uploads/2026/07/Holiday-list-2027.pdf", "https://www.hinduamerican.org/wp-content/uploads/2025/12/1.26_000.01-2026-Dharmic-Calendar.pdf"],
            note: "This is the main Lakshmi Puja day only. The Hindu American Foundation shows the 2026 festival as 5-10 November, with the main day on 8 November. DoPT notes that some states observe Naraka Chaturdashi, the day before, as Deepavali. 2028-2030 rest on Drik Panchang alone.", isProvisional: false,
            occurrences: [("2026-11-08", "2026-11-08"), ("2027-10-29", "2027-10-29"), ("2028-10-17", "2028-10-17"), ("2029-11-05", "2029-11-05"), ("2030-10-26", "2030-10-26")]),
        "vaisakhi": PublishedDates(
            tradition: "Sikh: 1 Vaisakh (SGPC Nanakshahi calendar); Mesha Sankranti, New Delhi (Drik Panchang) where SGPC is unpublished",
            authority: "SGPC calendar via SikhNet (2026); Government of India DoPT restricted holidays (2026, 2027); Drik Panchang, New Delhi (2028-2030)",
            sources: ["https://sikhnet.com/pages/sikh-gurpurab-calendar", "https://www.staffnews.in/wp-content/uploads/2025/07/Holidays-to-be-observed-in-Central-Government-Offices-during-the-year-2026.pdf", "https://www.staffnews.in/wp-content/uploads/2026/07/Holiday-list-2027.pdf", "https://www.drikpanchang.com/festivals/vaisakhi/vaisakhi-date-time.html?geoname-id=1261481&year=2028", "https://www.drikpanchang.com/festivals/vaisakhi/vaisakhi-date-time.html?geoname-id=1261481&year=2029", "https://www.drikpanchang.com/festivals/vaisakhi/vaisakhi-date-time.html?geoname-id=1261481&year=2030"],
            note: "SikhNet's calendar (Nanakshahi Samat 558, 'as per SGPC Calendar') lists Khalsa Saajna Divas on 14 April 2026, 01 Vaisakh. SGPC's calendars for 2027 onwards are not published yet. 2028-2030 are Drik Panchang's Mesha Sankranti dates for New Delhi, not a Sikh authority's. SGPC's traditional reckoning could differ, so recheck them when each Jantri is published. The Hindu American Foundation's US calendar lists 13 April for 2026.", isProvisional: false,
            occurrences: [("2026-04-14", "2026-04-14"), ("2027-04-14", "2027-04-14"), ("2028-04-13", "2028-04-13"), ("2029-04-14", "2029-04-14"), ("2030-04-14", "2030-04-14")]),
        "bandi-chhor-divas": PublishedDates(
            tradition: "Sikh: SGPC Nanakshahi calendar (23 Katak in Samat 558)",
            authority: "SGPC calendar via SikhNet",
            sources: ["https://sikhnet.com/pages/sikh-gurpurab-calendar"],
            note: "SikhNet lists 'Bandi Chhor (Divali), 23 Katak' on 8 November 2026. SGPC observes it on Diwali, but no Sikh source publishes 2027-2030 yet. Those years are left out instead of being copied from the Diwali table.", isProvisional: false,
            occurrences: [("2026-11-08", "2026-11-08")]),
        "guru-nanak-gurpurab": PublishedDates(
            tradition: "Sikh: Guru Nanak Dev Ji Prakash Purab on Kattak Puranmashi (Kartika Purnima)",
            authority: "SGPC calendar via SikhNet (2026); Government of India DoPT (2026, 2027); Drik Panchang, New Delhi (2028-2030)",
            sources: ["https://sikhnet.com/pages/sikh-gurpurab-calendar", "https://www.staffnews.in/wp-content/uploads/2025/07/Holidays-to-be-observed-in-Central-Government-Offices-during-the-year-2026.pdf", "https://www.staffnews.in/wp-content/uploads/2026/07/Holiday-list-2027.pdf", "https://www.drikpanchang.com/calendars/indian/sikh-festivals/jayanti/guru-nanak-jayanti-date.html?geoname-id=1261481&year=2028", "https://www.drikpanchang.com/calendars/indian/sikh-festivals/jayanti/guru-nanak-jayanti-date.html?geoname-id=1261481&year=2029", "https://www.drikpanchang.com/calendars/indian/sikh-festivals/jayanti/guru-nanak-jayanti-date.html?geoname-id=1261481&year=2030"],
            note: "Drik Panchang (New Delhi) agrees with SGPC and DoPT for 2026 (24 Nov) and with DoPT for 2027 (14 Nov). 2028-2030 rest on Drik Panchang alone, so recheck them when each SGPC Jantri is published.", isProvisional: false,
            occurrences: [("2026-11-24", "2026-11-24"), ("2027-11-14", "2027-11-14"), ("2028-11-02", "2028-11-02"), ("2029-11-21", "2029-11-21"), ("2030-11-10", "2030-11-10")]),
        "eid-al-fitr": PublishedDates(
            tradition: "Islamic (Hijri) calendar, 1 Shawwal: Fiqh Council of North America calculation, identical to Saudi Umm al-Qura for these years",
            authority: "Fiqh Council of North America; Umm al-Qura (via moonsighting.com)",
            sources: ["https://fiqhcouncil.org/calendar/", "https://www.moonsighting.com/fcna-uq-calendar.html"],
            note: "Begins at sunset the evening before start. FCNA's calendar quotes these as 'Eid - Shawwal 1' for 1447-1451 AH, and moonsighting.com shows the same Umm al-Qura dates. Communities that rely on local sighting may observe a day later; India's DoPT lists 21 March 2026 and 10 March 2027, for example.", isProvisional: true,
            occurrences: [("2026-03-20", "2026-03-20"), ("2027-03-09", "2027-03-09"), ("2028-02-26", "2028-02-26"), ("2029-02-14", "2029-02-14"), ("2030-02-04", "2030-02-04")]),
        "eid-al-adha": PublishedDates(
            tradition: "Islamic (Hijri) calendar, 10 Dhul Hijjah: FCNA / Umm al-Qura month starts",
            authority: "Fiqh Council of North America; Umm al-Qura (via moonsighting.com)",
            sources: ["https://fiqhcouncil.org/calendar/", "https://www.moonsighting.com/fcna-uq-calendar.html"],
            note: "Begins at sunset the evening before start. Both sources list 1 Dhul-Hijjah (18 May 2026, 7 May 2027, 26 Apr 2028, 15 Apr 2029, 4 Apr 2030), and start is that date plus 9 days. FCNA says Eid al-Adha is finally set as the day after Yawm 'Arafah, as determined by Saudi Arabia's Supreme Court. Local sighting can move it by a day; India moved 2026 to 28 May.", isProvisional: true,
            occurrences: [("2026-05-27", "2026-05-27"), ("2027-05-16", "2027-05-16"), ("2028-05-05", "2028-05-05"), ("2029-04-24", "2029-04-24"), ("2030-04-13", "2030-04-13")]),
        "hanukkah": PublishedDates(
            tradition: "Hebrew calendar (diaspora), 25 Kislev for 8 days",
            authority: "Chabad.org",
            sources: ["https://www.chabad.org/holidays/chanukah/article_cdo/aid/671899/jewish/When-Is-Hanukkah-Chanukah-Celebrated-in-2025-2026-2027-2028-2029-and-2030.htm"],
            note: "Begins at nightfall the evening before start, when the first candle is lit. Chabad lists evening-to-evening ranges (2026: 4-12 Dec; 2027: 24 Dec - 1 Jan 2028; 2028: 12-20 Dec; 2029: 1-9 Dec; 2030: 20-28 Dec). start is the first full civil day and end is the eighth day, which ends at nightfall.", isProvisional: false,
            occurrences: [("2026-12-05", "2026-12-12"), ("2027-12-25", "2028-01-01"), ("2028-12-13", "2028-12-20"), ("2029-12-02", "2029-12-09"), ("2030-12-21", "2030-12-28")]),
        "vesak": PublishedDates(
            tradition: "India: Buddha Purnima (Vaishakha Purnima), New Delhi",
            authority: "Government of India DoPT (2026, 2027); Drik Panchang, New Delhi (all years); Hindu American Foundation (2026)",
            sources: ["https://www.staffnews.in/wp-content/uploads/2025/07/Holidays-to-be-observed-in-Central-Government-Offices-during-the-year-2026.pdf", "https://www.staffnews.in/wp-content/uploads/2026/07/Holiday-list-2027.pdf", "https://www.drikpanchang.com/festivals/buddha-purnima/buddha-purnima-date-time.html?geoname-id=1261481&year=2026", "https://www.drikpanchang.com/festivals/buddha-purnima/buddha-purnima-date-time.html?geoname-id=1261481&year=2027", "https://www.drikpanchang.com/festivals/buddha-purnima/buddha-purnima-date-time.html?geoname-id=1261481&year=2028", "https://www.drikpanchang.com/festivals/buddha-purnima/buddha-purnima-date-time.html?geoname-id=1261481&year=2029", "https://www.drikpanchang.com/festivals/buddha-purnima/buddha-purnima-date-time.html?geoname-id=1261481&year=2030", "https://www.hinduamerican.org/wp-content/uploads/2025/12/1.26_000.01-2026-Dharmic-Calendar.pdf"],
            note: "These are India's Buddha Purnima dates, not the UN Day of Vesak, which has no published future table. Other countries differ. Thailand's Visakha Bucha in 2026 was 31 May (Bank of Thailand), for example. 2028-2030 rest on Drik Panchang alone.", isProvisional: false,
            occurrences: [("2026-05-01", "2026-05-01"), ("2027-05-20", "2027-05-20"), ("2028-05-08", "2028-05-08"), ("2029-05-27", "2029-05-27"), ("2030-05-17", "2030-05-17")]),
    ]
}

/// One edition's published annual dates and where they come from.
struct PublishedDates {
    let tradition: String
    let authority: String
    let sources: [String]
    let note: String?
    let isProvisional: Bool
    let occurrences: [(start: String, end: String)]

    var ranges: [CivilDayRange] {
        occurrences.compactMap { occurrence in
            CivilDate(occurrence.start).flatMap { start in
                CivilDate(occurrence.end).flatMap { CivilDayRange(first: start, last: $0) }
            }
        }
    }
}
