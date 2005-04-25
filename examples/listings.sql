-- MySQL dump 9.11
--
-- Host: localhost    Database: listings
-- ------------------------------------------------------
-- Server version	4.0.23_Debian-4-log

--
-- Table structure for table `batches`
--

DROP TABLE IF EXISTS `batches`;
CREATE TABLE `batches` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(50) NOT NULL default '',
  `last_update` int(11) NOT NULL default '0',
  PRIMARY KEY  (`id`)
) TYPE=InnoDB;

--
-- Table structure for table `channels`
--

DROP TABLE IF EXISTS `channels`;
CREATE TABLE `channels` (
  `id` int(11) NOT NULL auto_increment,
  `display_name` varchar(100) NOT NULL default '',
  `xmltvid` varchar(100) NOT NULL default '',
  `grabber` varchar(20) NOT NULL default '',
  `export` tinyint(1) NOT NULL default '0',
  `grabber_info` varchar(100) NOT NULL default '',
  `logo` tinyint(4) NOT NULL default '0',
  `def_pty` varchar(20) default '',
  `def_cat` varchar(20) default '',
  `sched_lang` varchar(4) NOT NULL default '',
  PRIMARY KEY  (`id`)
) TYPE=InnoDB;

--
-- Table structure for table `programs`
--

DROP TABLE IF EXISTS `programs`;
CREATE TABLE `programs` (
  `category` varchar(100) NOT NULL default '',
  `channel_id` int(11) NOT NULL default '0',
  `start_time` datetime NOT NULL default '0000-00-00 00:00:00',
  `end_time` datetime default '0000-00-00 00:00:00',
  `title` varchar(100) NOT NULL default '',
  `subtitle` mediumtext,
  `description` mediumtext,
  `batch_id` int(11) NOT NULL default '0',
  `program_type` varchar(20) default '',
  `episode` varchar(20) default NULL,
  PRIMARY KEY  (`channel_id`,`start_time`),
  KEY `channel_id` (`channel_id`,`start_time`),
  KEY `batch` (`batch_id`,`start_time`)
) TYPE=InnoDB;

--
-- Table structure for table `state`
--

DROP TABLE IF EXISTS `state`;
CREATE TABLE `state` (
  `name` varchar(60) NOT NULL default '',
  `value` text,
  PRIMARY KEY  (`name`)
) TYPE=InnoDB;

--
-- Table structure for table `trans_cat`
--

DROP TABLE IF EXISTS `trans_cat`;
CREATE TABLE `trans_cat` (
  `type` varchar(20) NOT NULL default '',
  `original` varchar(50) NOT NULL default '',
  `category` varchar(20) default '',
  `program_type` varchar(50) default '',
  PRIMARY KEY  (`type`,`original`)
) TYPE=InnoDB;

-- MySQL dump 9.11
--
-- Host: localhost    Database: listings
-- ------------------------------------------------------
-- Server version	4.0.23_Debian-4-log

--
-- Dumping data for table `channels`
--

INSERT INTO `channels` VALUES (1,'TV3','tv3.viasat.se','Viasat',1,'tv3_se_',0,'','','sv');
INSERT INTO `channels` VALUES (2,'TV1000','tv1000.viasat.se','Viasat',1,'tv1000_se_',0,'','','sv');
INSERT INTO `channels` VALUES (3,'Kanal 5','kanal5.se','Kanal5',1,'',0,'','','sv');
INSERT INTO `channels` VALUES (5,'TV4','tv4.se','TV4',1,'1',0,'','','sv');
INSERT INTO `channels` VALUES (6,'TV4 Plus','plus.tv4.se','TV4',1,'3',0,'','','sv');
INSERT INTO `channels` VALUES (8,'TV4 Film','film.tv4.se','TV4',1,'5',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (9,'TV1000 Nordic','nordic.tv1000.viasat.se','Viasat',1,'tv1000_nordic_se_',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (10,'TV1000 Action','action.tv1000.viasat.se','Viasat',1,'tv1000_action_se_',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (11,'TV1000 Family','family.tv1000.viasat.se','Viasat',1,'tv1000_family_se_',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (12,'TV1000 Classic','classic.tv1000.viasat.se','Viasat',1,'tv1000_classic_se_',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (13,'ZTV','ztv.se','Viasat',1,'ztv_se_',0,'','','sv');
INSERT INTO `channels` VALUES (14,'Viasat Sport 1','sport1.viasat.se','Viasat',1,'viasat_sport_1_se_',0,'sports','Sports','sv');
INSERT INTO `channels` VALUES (15,'Viasat Sport 2','sport2.viasat.se','Viasat',1,'viasat_sport_2_se_',0,'sports','Sports','sv');
INSERT INTO `channels` VALUES (16,'Viasat Sport 3','sport3.viasat.se','Viasat',1,'viasat_sport_3_se_',0,'sports','Sports','sv');
INSERT INTO `channels` VALUES (17,'Viasat Explorer','explorer.viasat.se','Viasat',1,'viasat_explorer_se_',0,'','','sv');
INSERT INTO `channels` VALUES (18,'Viasat Nature/Action','action.viasat.se','Viasat',1,'viasat_nature_action_se_',0,'','','sv');
INSERT INTO `channels` VALUES (19,'Ticket 1','ticket1.viasat.se','Viasat',1,'ticket_1_-_premium_movies_se_',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (20,'TV8','tv8.se','Viasat',1,'tv8_se_',0,'','','sv');
INSERT INTO `channels` VALUES (21,'Viasat History','history.viasat.se','Viasat',1,'viasat_history_se_',0,'','','sv');
INSERT INTO `channels` VALUES (22,'Canal+','canalplus.se','CanalPlus',1,'1',0,'','','sv');
INSERT INTO `channels` VALUES (23,'Canal+ Film1','film1.canalplus.se','CanalPlus',1,'4',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (24,'Canal+ Film2','film2.canalplus.se','CanalPlus',1,'5',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (25,'C More Film','cmorefilm.canalplus.se','CanalPlus',1,'8',0,'movie','Movies','sv');
INSERT INTO `channels` VALUES (26,'Canal+ Sport','sport.canalplus.se','CanalPlus',1,'6',0,'sports','Sports','sv');
INSERT INTO `channels` VALUES (27,'Barnkanalen','barnkanalen.svt.se','Svt',1,'Barnkanalen',0,'','Children\'s','sv');
INSERT INTO `channels` VALUES (28,'Svt 1','svt1.svt.se','Svt',1,'SVT 1',0,'','','sv');
INSERT INTO `channels` VALUES (29,'Svt 2','svt2.svt.se','Svt',1,'SVT 2',0,'','','sv');
INSERT INTO `channels` VALUES (30,'Eurosport','eurosport.com','Eurosport',1,'',0,'sports','Sports','sv');
INSERT INTO `channels` VALUES (31,'TV400','tv400.tv4.se','TV4',1,'6',0,'','','sv');
INSERT INTO `channels` VALUES (32,'Discovery Channel','nordic.discovery.com','Discovery',1,'DC.NO',0,'','','sv');
INSERT INTO `channels` VALUES (33,'Animal Planet','nordic.animalplanet.discovery.com','Discovery',1,'AP.NO',0,'','','sv');
INSERT INTO `channels` VALUES (34,'MTV Nordic','nordic.mtve.com','Mtve',1,'MTV Nordic',0,'','','en');
INSERT INTO `channels` VALUES (35,'Kunskapskanalen','kunskapskanalen.svt.se','Svt',1,'Kunskapskanalen',0,'','','sv');
INSERT INTO `channels` VALUES (36,'SVT 24','svt24.svt.se','Svt',1,'24',0,'','','sv');
INSERT INTO `channels` VALUES (37,'SVT Extra','extra.svt.se','Svt',1,'SVT Extra',0,'','','sv');
INSERT INTO `channels` VALUES (38,'Disney Channel','disneychannel.se','Infomedia',1,'1324',0,'','Children\'s','sv');
INSERT INTO `channels` VALUES (39,'Al Jazeera','aljazeera.net','Infomedia',1,'37',0,'','','en');
INSERT INTO `channels` VALUES (40,'Discovery Civilisation','nordic.civilisation.discovery.com','Discovery',1,'CI.EU',0,'','','sv');
INSERT INTO `channels` VALUES (41,'Discovery Travel & Living','nordic.travel.discovery.com','Discovery',1,'TL.EU',0,'','','sv');
INSERT INTO `channels` VALUES (42,'Discovery Science','nordic.science.discovery.com','Discovery',1,'SC.EU',0,'','','sv');
INSERT INTO `channels` VALUES (43,'Discovery Mix','nordic.mix.discovery.com','Combiner',1,'',0,'','','sv');
INSERT INTO `channels` VALUES (44,'Kunskap/Barnkanalen','kunskapbarn.svt.se','Combiner',1,'',0,'','','sv');

--
-- Dumping data for table `trans_cat`
--

INSERT INTO `trans_cat` VALUES ('Kanal5','Adventure/Nature','','');
INSERT INTO `trans_cat` VALUES ('Kanal5','Children','','');
INSERT INTO `trans_cat` VALUES ('Kanal5','Documentary','Documentary','');
INSERT INTO `trans_cat` VALUES ('Kanal5','Film','','movie');
INSERT INTO `trans_cat` VALUES ('Kanal5','Magazine','','');
INSERT INTO `trans_cat` VALUES ('Kanal5','Series','','series');
INSERT INTO `trans_cat` VALUES ('Kanal5','Specials','','');
INSERT INTO `trans_cat` VALUES ('Kanal5','Sport','','sports');
INSERT INTO `trans_cat` VALUES ('Kanal5','Talkshows','','tvshow');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Adventure/Nature','Kanal5-Adventure','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Children','Children\'s','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Documentary','','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Film','Movies','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Magazine','Kanal5-Magazine','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Series','','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Specials','Kanal5-Specials','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Sport','Sports','');
INSERT INTO `trans_cat` VALUES ('Kanal5_fallback','Talkshows','Talk','');
INSERT INTO `trans_cat` VALUES ('Svt','Barn','Children\'s','');
INSERT INTO `trans_cat` VALUES ('Svt','Drama','','');
INSERT INTO `trans_cat` VALUES ('Svt','Fakta','','');
INSERT INTO `trans_cat` VALUES ('Svt','Film','','movie');
INSERT INTO `trans_cat` VALUES ('Svt','Fritid','','');
INSERT INTO `trans_cat` VALUES ('Svt','Kultur','','');
INSERT INTO `trans_cat` VALUES ('Svt','Musik/Dans','Music','');
INSERT INTO `trans_cat` VALUES ('Svt','Nyheter','News','');
INSERT INTO `trans_cat` VALUES ('Svt','Nöje','Svt-Nöje','');
INSERT INTO `trans_cat` VALUES ('Svt','Samhälle','Documentary','');
INSERT INTO `trans_cat` VALUES ('Svt','Sport','Sports','sports');
INSERT INTO `trans_cat` VALUES ('Svt','Unclassified','','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Barn','','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Drama','Svt-Drama','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Fakta','Svt-Fakta','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Film','Movies','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Fritid','Svt-Fritid','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Kultur','Svt-Kultur','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Musik/Dans','','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Nyheter','','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Nöje','','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Samhälle','','');
INSERT INTO `trans_cat` VALUES ('Svt_fallback','Sport','','');
INSERT INTO `trans_cat` VALUES ('Viasat_category','FILMER','Movies','movie');
INSERT INTO `trans_cat` VALUES ('Viasat_category','MINISERIER','','series');
INSERT INTO `trans_cat` VALUES ('Viasat_category','MUSIK','Music','');
INSERT INTO `trans_cat` VALUES ('Viasat_category','NYHETER/DOKUMENTÄRER','News','');
INSERT INTO `trans_cat` VALUES ('Viasat_category','SERIER','','series');
INSERT INTO `trans_cat` VALUES ('Viasat_category','SPORT','Sports','sports');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Komedi.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Komedi/Familj.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Reality/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Science-fiction.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Thriller.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Thriller/Deckare.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Thriller/Komedi.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Thriller/Science-fiction.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Western.','Action','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Äventyr.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Äventyr/Komedi.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Äventyr/Krig.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Action/Äventyr/Reality.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Barn.','Children\'s','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Deckare.','Crime','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Dokumentär.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Dokumentär/Natur.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Dokumentär/Reality.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Dokumentär/Specialmagasin.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Dokumentär/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Action.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Action/Deckare.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Action/Krig.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Action/Thriller.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Action/Äventyr.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Deckare.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Deckare/Deckare.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Deckare/Science-fiction.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Familj.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Familj/Fantasy.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Film Noir/Krig.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Komedi.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Komedi/Familj.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Komedi/Familj/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Komedi/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Komedi/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Krig.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Kärlek/Krig.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Musikal.','Musical','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Science-fiction.','SciFi','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Skräck.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Thriller.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Thriller/Deckare.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Western.','Drama','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Äventyr.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Drama/Äventyr/Familj.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Erotik (klippt version).','Adult','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Erotik.','Adult','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Familj/Barn.','Kids','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Familj/Musikal.','Musical','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Familj/Reality/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Familj/Science-fiction.','SciFi','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Gameshow.','Game','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Deckare.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Deckare/Musikal.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Familj.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Familj/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Familj/Musikal.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Fantasy/Skräck.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Musikal.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Musikal/Science-fiction.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Science-fiction.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Skräck.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Komedi/Talkshow/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Musikal.','Musical','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Reality.','Reality','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Reality/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Skräck.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Specialmagasin.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Talkshow.','Talk','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Talkshow/Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Tecknat.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Tecknat/Barn.','Children\'s','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Tecknat/Familj.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Tecknat/Familj/Barn.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Tecknat/Komedi.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Tecknat/Komedi/Familj.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller.','Mystery','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller/Deckare.','Mystery','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller/Film Noir/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller/Komedi.','Comedy','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller/Science-fiction.','SciFi','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Thriller/Skräck.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Underhållning.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Western.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Dokumentär.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Familj.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Familj/Deckare.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Familj/Fantasy.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Komedi.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Komedi/Familj.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Kärlek.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Tecknat.','','');
INSERT INTO `trans_cat` VALUES ('Viasat_genre','Äventyr/Tecknat/Familj.','','');

