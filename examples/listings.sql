--
-- Table structure for table `batches`
--

CREATE TABLE `batches` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(50) NOT NULL default '',
  `last_update` int(11) NOT NULL default '0',
  PRIMARY KEY  (`id`)
) TYPE=MyISAM;

--
-- Dumping data for table `batches`
--


--
-- Table structure for table `channels`
--

CREATE TABLE `channels` (
  `id` int(11) NOT NULL auto_increment,
  `display_name` varchar(100) NOT NULL default '',
  `xmltvid` varchar(100) NOT NULL default '',
  `grabber` varchar(20) NOT NULL default '',
  `grabber_info` varchar(100) NOT NULL default '',
  PRIMARY KEY  (`id`)
) TYPE=MyISAM;

--
-- Dumping data for table `channels`
--

INSERT INTO `channels` VALUES (1,'Tv 3','tv3.viasat.se','Viasat','tv3_se_');
INSERT INTO `channels` VALUES (2,'TV 1000','tv1000.viasat.se','Viasat','tv1000_se_');
INSERT INTO `channels` VALUES (3,'Kanal 5','kanal5.se','Kanal5','');
INSERT INTO `channels` VALUES (4,'Svt 1','svt1.svt.se','Svt','SVT 1');
INSERT INTO `channels` VALUES (5,'TV4','tv4.se','TV4','1');
INSERT INTO `channels` VALUES (6,'TV4 Plus','plus.tv4.se','TV4','3');
INSERT INTO `channels` VALUES (7,'TV4 Med i tv','meditv.tv4.se','TV4','4');
INSERT INTO `channels` VALUES (8,'TV4 Film','film.tv4.se','TV4','5');
INSERT INTO `channels` VALUES (9,'TV 1000 Nordic','nordic.tv1000.viasat.se','Viasat','tv1000_nordic_se_');
INSERT INTO `channels` VALUES (10,'TV 1000 Action','action.tv1000.viasat.se','Viasat','tv1000_action_se_');
INSERT INTO `channels` VALUES (11,'TV 1000 Family','family.tv1000.viasat.se','Viasat','tv1000_family_se_');
INSERT INTO `channels` VALUES (12,'TV 1000 Classic','classic.tv1000.viasat.se','Viasat','tv1000_classic_se_');
INSERT INTO `channels` VALUES (13,'ZTV','ztv.se','Viasat','ztv_se_');
INSERT INTO `channels` VALUES (14,'Viasat Sport 1','sport1.viasat.se','Viasat','viasat_sport_1_se_');
INSERT INTO `channels` VALUES (15,'Viasat Sport 2','sport2.viasat.se','Viasat','viasat_sport_2_se_');
INSERT INTO `channels` VALUES (16,'Viasat Sport 3','sport3.viasat.se','Viasat','viasat_sport_3_se_');
INSERT INTO `channels` VALUES (17,'Viasat Explorer','explorer.viasat.se','Viasat','viasat_explorer_se_');
INSERT INTO `channels` VALUES (18,'Viasat Nature/Action','action.viasat.se','Viasat','viasat_nature_action_se_');
INSERT INTO `channels` VALUES (19,'Ticket 1','ticket1.viasat.se','Viasat','ticket_1_-_premium_movies_se_');
INSERT INTO `channels` VALUES (20,'TV 8','tv8.se','Viasat','tv8_se_');

--
-- Table structure for table `programs`
--

CREATE TABLE `programs` (
  `channel_id` int(11) NOT NULL default '0',
  `start_time` datetime NOT NULL default '0000-00-00 00:00:00',
  `end_time` datetime NOT NULL default '0000-00-00 00:00:00',
  `title` varchar(100) NOT NULL default '',
  `description` mediumtext,
  `episode_nr` bigint(20) default '0',
  `season_nr` bigint(20) default '0',
  `batch_id` int(11) NOT NULL default '0',
  KEY `channel_id` (`channel_id`,`start_time`)
) TYPE=MyISAM;

--
-- Dumping data for table `programs`
--


--
-- Table structure for table `state`
--

CREATE TABLE `state` (
  `name` varchar(60) NOT NULL default '',
  `value` text,
  PRIMARY KEY  (`name`)
) TYPE=MyISAM;

--
-- Dumping data for table `state`
--


