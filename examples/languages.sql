
-- 
-- Table structure for table `lang_en`
-- 

CREATE TABLE `lang_en` (
  `module` varchar(32) NOT NULL,
  `strname` varchar(32) NOT NULL,
  `strvalue` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- 
-- Dumping data for table `lang_en`
-- 

INSERT INTO `lang_en` (`module`, `strname`, `strvalue`) VALUES ('exporter-xmltv', 'episode_part', 'part'),
('exporter-xmltv', 'episode_number', 'episode'),
('exporter-xmltv', 'episode_season', 'season'),
('exporter-xmltv', 'of', 'of'),
('listchannels', 'title', 'This is the title of your channel listing page.'),
('listchannels', 'headertext', 'Put whatever you want here. It will be displayed on the top of the channel list.'),
('listchannels', 'channel', 'Channel'),
('listchannels', 'xmltvid', 'XMLTV ID'),
('listchannels', 'datasource', 'Source'),
('listchannels', 'footertext', 'Put whatever you want here. It will be displayed on the bottom of the channel list.');

-- 
-- Table structure for table `lang_hr`
-- 

CREATE TABLE `lang_hr` (
  `module` varchar(32) NOT NULL,
  `strname` varchar(32) NOT NULL,
  `strvalue` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- 
-- Dumping data for table `lang_hr`
-- 

INSERT INTO `lang_hr` (`module`, `strname`, `strvalue`) VALUES ('exporter-xmltv', 'episode_part', 'dio'),
('exporter-xmltv', 'episode_number', 'epizoda'),
('exporter-xmltv', 'episode_season', 'sezona'),
('exporter-xmltv', 'of', 'od'),
('listchannels', 'title', 'Kanali za koje goNIX ima raspored emitiranja'),
('listchannels', 'headertext', 'Rasporedi programa svih navedenih kanala nalaze se u <a href="/xmltv/">XMLTV</a> direktoriju. Za svaki dan i svaki kanal kreira se po jedan file.'),
('listchannels', 'channel', 'Kanal'),
('listchannels', 'xmltvid', 'XMLTV ID'),
('listchannels', 'datasource', 'Izvor'),
('listchannels', 'footertext', '');

-- 
-- Table structure for table `lang_se`
-- 

CREATE TABLE `lang_se` (
  `module` varchar(32) NOT NULL,
  `strname` varchar(32) NOT NULL,
  `strvalue` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

-- 
-- Dumping data for table `lang_se`
-- 

INSERT INTO `lang_se` (`module`, `strname`, `strvalue`) VALUES ('exporter-xmltv', 'episode_part', 'Part'),
('exporter-xmltv', 'episode_number', 'Del'),
('exporter-xmltv', 'episode_season', 'säng'),
('exporter-xmltv', 'of', 'av'),
('listchannels', 'title', 'This is the title of your channel listing page.'),
('listchannels', 'headertext', 'Put whatever you want here. It will be displayed on the top of the channel list.'),
('listchannels', 'channel', 'Channel'),
('listchannels', 'xmltvid', 'XMLTV ID'),
('listchannels', 'datasource', 'Source'),
('listchannels', 'footertext', 'Put whatever you want here. It will be displayed on the bottom of the channel list.');

