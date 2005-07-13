-- MySQL dump 10.9
--
-- Host: localhost    Database: listings
-- ------------------------------------------------------
-- Server version	4.1.11-Debian_4

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `batches`
--

DROP TABLE IF EXISTS `batches`;
CREATE TABLE `batches` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(50) NOT NULL default '',
  `last_update` int(11) NOT NULL default '0',
  `message` text NOT NULL,
  `abort_message` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

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
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

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
  `production_date` date default NULL,
  `aspect` enum('unknown','4:3','16:9') NOT NULL default 'unknown',
  `directors` text NOT NULL,
  `actors` text NOT NULL,
  PRIMARY KEY  (`channel_id`,`start_time`),
  KEY `channel_id` (`channel_id`,`start_time`),
  KEY `batch` (`batch_id`,`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

--
-- Table structure for table `state`
--

DROP TABLE IF EXISTS `state`;
CREATE TABLE `state` (
  `name` varchar(60) NOT NULL default '',
  `value` text,
  PRIMARY KEY  (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

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
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- MySQL dump 10.9
--
-- Host: localhost    Database: listings
-- ------------------------------------------------------
-- Server version	4.1.11-Debian_4

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping data for table `channels`
--


/*!40000 ALTER TABLE `channels` DISABLE KEYS */;
LOCK TABLES `channels` WRITE;
INSERT INTO `channels` VALUES (1,'TV3','tv3.viasat.se','Viasat',1,'tv3_se_',1,'','','sv'),(2,'TV1000','tv1000.viasat.se','Viasat',1,'tv1000_se_',0,'','','sv'),(3,'Kanal 5','kanal5.se','Kanal5',1,'',1,'','','sv'),(5,'TV4','tv4.se','TV4',1,'1',1,'','','sv'),(6,'TV4 Plus','plus.tv4.se','TV4',1,'3',1,'','','sv'),(8,'TV4 Film','film.tv4.se','TV4',1,'5',1,'movie','Movies','sv'),(9,'TV1000 Nordic','nordic.tv1000.viasat.se','Viasat',1,'tv1000_nordic_se_',0,'movie','Movies','sv'),(10,'TV1000 Action','action.tv1000.viasat.se','Viasat',1,'tv1000_action_se_',0,'movie','Movies','sv'),(11,'TV1000 Family','family.tv1000.viasat.se','Viasat',1,'tv1000_family_se_',0,'movie','Movies','sv'),(12,'TV1000 Classic','classic.tv1000.viasat.se','Viasat',1,'tv1000_classic_se_',0,'movie','Movies','sv'),(13,'ZTV','ztv.se','Viasat',1,'ztv_se_',1,'','','sv'),(14,'Viasat Sport 1','sport1.viasat.se','Viasat',1,'viasat_sport_1_se_',1,'sports','Sports','sv'),(15,'Viasat Sport 2','sport2.viasat.se','Viasat',1,'viasat_sport_2_se_',1,'sports','Sports','sv'),(16,'Viasat Sport 3','sport3.viasat.se','Viasat',1,'viasat_sport_3_se_',1,'sports','Sports','sv'),(17,'Viasat Explorer','explorer.viasat.se','Viasat',1,'viasat_explorer_se_',1,'','','sv'),(18,'Viasat Nature/Action','action.viasat.se','Viasat',1,'viasat_nature_action_se_',1,'','','sv'),(19,'Ticket 1','ticket1.viasat.se','Viasat',1,'ticket_1_-_premium_movies_se_',0,'movie','Movies','sv'),(20,'TV8','tv8.se','Viasat',1,'tv8_se_',1,'','','sv'),(21,'Viasat History','history.viasat.se','Viasat',1,'viasat_history_se_',1,'','','sv'),(22,'Canal+','canalplus.se','CanalPlus',1,'1',1,'','','sv'),(23,'Canal+ Film1','film1.canalplus.se','CanalPlus',1,'4',1,'movie','Movies','sv'),(24,'Canal+ Film2','film2.canalplus.se','CanalPlus',1,'5',1,'movie','Movies','sv'),(25,'C More Film','cmorefilm.canalplus.se','CanalPlus',1,'8',1,'movie','Movies','sv'),(26,'Canal+ Sport','sport.canalplus.se','CanalPlus',1,'6',1,'sports','Sports','sv'),(27,'Barnkanalen','barnkanalen.svt.se','Svt',1,'Barnkanalen',1,'','Children\'s','sv'),(28,'Svt 1','svt1.svt.se','Svt',1,'SVT 1',1,'','','sv'),(29,'Svt 2','svt2.svt.se','Svt',1,'SVT 2',1,'','','sv'),(30,'Eurosport','eurosport.com','Eurosport',1,'tv_schedule_mogador_10000_7.xml',0,'sports','Sports','sv'),(31,'TV400','tv400.tv4.se','TV4',1,'6',1,'','','sv'),(32,'Discovery Channel','nordic.discovery.com','Discovery',1,'DC.NO',1,'','','sv'),(33,'Animal Planet','nordic.animalplanet.discovery.com','Discovery',1,'AP.NO',1,'','','sv'),(34,'MTV Nordic','nordic.mtve.com','Mtve',1,'MTV Sweden',1,'','','en'),(35,'Kunskapskanalen','kunskapskanalen.svt.se','Svt',1,'Kunskapskanalen',1,'','','sv'),(36,'SVT 24','svt24.svt.se','Svt',1,'24',1,'','','sv'),(37,'SVT Extra','extra.svt.se','Svt',1,'SVT Extra',1,'','','sv'),(38,'Disney Channel','disneychannel.se','Infomedia',1,'1324',0,'','Children\'s','sv'),(39,'Al Jazeera','aljazeera.net','Infomedia',1,'37',0,'','','en'),(40,'Discovery Civilisation','nordic.civilisation.discovery.com','Discovery',1,'CI.EU',0,'','','sv'),(41,'Discovery Travel & Living','nordic.travel.discovery.com','Discovery',1,'TL.EU',1,'','','sv'),(42,'Discovery Science','nordic.science.discovery.com','Discovery',1,'SC.EU',0,'','','sv'),(43,'Discovery Mix','nordic.mix.discovery.com','Combiner',1,'',0,'','','sv'),(44,'Kunskap/Barnkanalen','kunskapbarn.svt.se','Combiner',1,'',0,'','','sv'),(45,'Sport-Expressen','sport.expressen.se','Expressen',1,'',0,'sports','Sports','sv'),(46,'Eurosport 2','eurosport2.eurosport.com','Eurosport',1,'tv_schedule_mogador_15000_7.xml',0,'sports','Sports','sv');
UNLOCK TABLES;
/*!40000 ALTER TABLE `channels` ENABLE KEYS */;

--
-- Dumping data for table `trans_cat`
--


/*!40000 ALTER TABLE `trans_cat` DISABLE KEYS */;
LOCK TABLES `trans_cat` WRITE;
INSERT INTO `trans_cat` VALUES ('CanalPlus','action','Action',''),('CanalPlus','actiondrama','',''),('CanalPlus','actionkomedi','Action',''),('CanalPlus','actionthriller','Action',''),('CanalPlus','actionäventyr','',''),('CanalPlus','allsvensk fotboll studio','',''),('CanalPlus','allsvenskan','',''),('CanalPlus','animé','',''),('CanalPlus','animerad serie','',''),('CanalPlus','avslutning','',''),('CanalPlus','avslutning med tipsredovisning','',''),('CanalPlus','basket','Sports',''),('CanalPlus','deckare','',''),('CanalPlus','deckarserie','Crime',''),('CanalPlus','dokumentär','',''),('CanalPlus','drama','Drama',''),('CanalPlus','dramadokumentär','',''),('CanalPlus','dramakomedi','Drama',''),('CanalPlus','dramaserie','Drama',''),('CanalPlus','dramathriller','Drama',''),('CanalPlus','engelsk ligafotboll','Sports',''),('CanalPlus','erotik','Adult',''),('CanalPlus','erotikserie','',''),('CanalPlus','erotiskt drama','Adult',''),('CanalPlus','familjeaction','Action',''),('CanalPlus','familjedrama','',''),('CanalPlus','familjefilm','',''),('CanalPlus','familjeäventyr','',''),('CanalPlus','filmdokumentär','',''),('CanalPlus','filmintervju','Talk',''),('CanalPlus','filmmagasin med hans wiklund','Magazine',''),('CanalPlus','hajskräck','',''),('CanalPlus','intervju','Talk',''),('CanalPlus','intervjuprogram','',''),('CanalPlus','ishockey','',''),('CanalPlus','italiensk ligafotboll','Sports',''),('CanalPlus','komedi','Comedy',''),('CanalPlus','komediserie','',''),('CanalPlus','kortfilm','',''),('CanalPlus','kortfilmsmagasin','',''),('CanalPlus','kostymkomedi','',''),('CanalPlus','krigsdrama','',''),('CanalPlus','krigsthriller','',''),('CanalPlus','krigsäventyr','',''),('CanalPlus','kriminaldrama','',''),('CanalPlus','kriminalkomedi','',''),('CanalPlus','kung fu','',''),('CanalPlus','kärleksdrama','',''),('CanalPlus','miniserie','',''),('CanalPlus','musikal','',''),('CanalPlus','musikdokumentär','',''),('CanalPlus','musikfilm','',''),('CanalPlus','romantisk komedi','',''),('CanalPlus','romantiskt drama','',''),('CanalPlus','rysare','',''),('CanalPlus','rysarserie','',''),('CanalPlus','sci fi-action','',''),('CanalPlus','sci fi-thriller','',''),('CanalPlus','science fiction','',''),('CanalPlus','skräck','',''),('CanalPlus','skräckfilm','',''),('CanalPlus','snutserie','',''),('CanalPlus','sport','',''),('CanalPlus','studio','',''),('CanalPlus','studio inför matchen. programledare arne hegerfors','',''),('CanalPlus','studio med europatipset','',''),('CanalPlus','studioprogram med italiensk och engelsk fotboll.','',''),('CanalPlus','surfdokumentär','',''),('CanalPlus','talkshow','',''),('CanalPlus','tecknad familjefilm','',''),('CanalPlus','tecknad film','',''),('CanalPlus','tecknad satirserie','',''),('CanalPlus','thriller','',''),('CanalPlus','thrillerdrama','',''),('CanalPlus','thrillerkomedi','',''),('CanalPlus','västern','',''),('CanalPlus','western','',''),('CanalPlus','äventyr','',''),('CanalPlus','äventyrskomedi','',''),('CanalPlus','äventyrsthriller','',''),('Kanal5','adventure/nature','',''),('Kanal5','children','',''),('Kanal5','documentary','Documentary',''),('Kanal5','film','','movie'),('Kanal5','magazine','',''),('Kanal5','series','','series'),('Kanal5','specials','',''),('Kanal5','sport','','sports'),('Kanal5','talkshows','','tvshow'),('Kanal5_fallback','adventure/nature','Kanal5-Adventure',''),('Kanal5_fallback','children','Children\'s',''),('Kanal5_fallback','documentary','',''),('Kanal5_fallback','film','Movies',''),('Kanal5_fallback','magazine','Kanal5-Magazine',''),('Kanal5_fallback','series','',''),('Kanal5_fallback','specials','Kanal5-Specials',''),('Kanal5_fallback','sport','Sports',''),('Kanal5_fallback','talkshows','Talk',''),('Svt','barn','Children\'s',''),('Svt','drama','',''),('Svt','fakta','',''),('Svt','film','','movie'),('Svt','fritid','',''),('Svt','kultur','',''),('Svt','musik/dans','Music',''),('Svt','nyheter','News',''),('Svt','nöje','Svt-Nöje',''),('Svt','samhälle','Documentary',''),('Svt','sport','Sports','sports'),('Svt','unclassified','',''),('Svt_fallback','barn','',''),('Svt_fallback','drama','Svt-Drama',''),('Svt_fallback','fakta','Svt-Fakta',''),('Svt_fallback','film','Movies',''),('Svt_fallback','fritid','Svt-Fritid',''),('Svt_fallback','kultur','Svt-Kultur',''),('Svt_fallback','musik/dans','',''),('Svt_fallback','nyheter','',''),('Svt_fallback','nöje','',''),('Svt_fallback','samhälle','',''),('Svt_fallback','sport','',''),('Viasat_category','filmer','Movies','movie'),('Viasat_category','miniserier','','series'),('Viasat_category','musik','Music',''),('Viasat_category','nyheter/dokumentärer','News',''),('Viasat_category','serier','','series'),('Viasat_category','sport','Sports','sports'),('Viasat_genre','','',''),('Viasat_genre','action','Action',''),('Viasat_genre','action/deckare','',''),('Viasat_genre','action/komedi','Action',''),('Viasat_genre','action/komedi/deckare','',''),('Viasat_genre','action/komedi/familj','Action',''),('Viasat_genre','action/komedi/fantasy','',''),('Viasat_genre','action/komedi/gangster','',''),('Viasat_genre','action/komedi/science-fiction','',''),('Viasat_genre','action/kärlek','',''),('Viasat_genre','action/reality/underhållning','',''),('Viasat_genre','action/science-fiction','Action',''),('Viasat_genre','action/skräck','',''),('Viasat_genre','action/tecknat/science-fiction','',''),('Viasat_genre','action/thriller','Action',''),('Viasat_genre','action/thriller/deckare','Action',''),('Viasat_genre','action/thriller/komedi','Action',''),('Viasat_genre','action/thriller/komedi/science-fiction','',''),('Viasat_genre','action/thriller/science-fiction','Action',''),('Viasat_genre','action/thriller/skräck','',''),('Viasat_genre','action/thriller/western','',''),('Viasat_genre','action/thriller/äventyr','',''),('Viasat_genre','action/western','Action',''),('Viasat_genre','action/äventyr','',''),('Viasat_genre','action/äventyr/fantasy','',''),('Viasat_genre','action/äventyr/fantasy/deckare/science-fiction','',''),('Viasat_genre','action/äventyr/komedi','',''),('Viasat_genre','action/äventyr/komedi/western','',''),('Viasat_genre','action/äventyr/krig','',''),('Viasat_genre','action/äventyr/reality','',''),('Viasat_genre','action/äventyr/science-fiction','',''),('Viasat_genre','barn','Children\'s',''),('Viasat_genre','deckare','Crime',''),('Viasat_genre','deckare/deckare','',''),('Viasat_genre','deckare/science-fiction','',''),('Viasat_genre','dokumentär','',''),('Viasat_genre','dokumentär/musikal','',''),('Viasat_genre','dokumentär/natur','',''),('Viasat_genre','dokumentär/reality','',''),('Viasat_genre','dokumentär/specialmagasin','',''),('Viasat_genre','dokumentär/underhållning','',''),('Viasat_genre','drama','Drama',''),('Viasat_genre','drama/action','Drama',''),('Viasat_genre','drama/action/deckare','Drama',''),('Viasat_genre','drama/action/komedi','',''),('Viasat_genre','drama/action/krig','Drama',''),('Viasat_genre','drama/action/thriller','Drama',''),('Viasat_genre','drama/action/äventyr','',''),('Viasat_genre','drama/deckare','Drama',''),('Viasat_genre','drama/deckare/deckare','Drama',''),('Viasat_genre','drama/deckare/gangster','',''),('Viasat_genre','drama/deckare/science-fiction','Drama',''),('Viasat_genre','drama/familj','Drama',''),('Viasat_genre','drama/familj/fantasy','Drama',''),('Viasat_genre','drama/fantasy','',''),('Viasat_genre','drama/film noir/krig','Drama',''),('Viasat_genre','drama/gangster','',''),('Viasat_genre','drama/komedi','Drama',''),('Viasat_genre','drama/komedi/familj','Drama',''),('Viasat_genre','drama/komedi/familj/kärlek','',''),('Viasat_genre','drama/komedi/krig','',''),('Viasat_genre','drama/komedi/kärlek','',''),('Viasat_genre','drama/komedi/underhållning','',''),('Viasat_genre','drama/krig','Drama',''),('Viasat_genre','drama/kärlek','',''),('Viasat_genre','drama/kärlek/krig','',''),('Viasat_genre','drama/musikal','Musical',''),('Viasat_genre','drama/musikal/kärlek','',''),('Viasat_genre','drama/science-fiction','SciFi',''),('Viasat_genre','drama/skräck','',''),('Viasat_genre','drama/thriller','Drama',''),('Viasat_genre','drama/thriller/deckare','Drama',''),('Viasat_genre','drama/thriller/krig','',''),('Viasat_genre','drama/western','Drama',''),('Viasat_genre','drama/äventyr','',''),('Viasat_genre','drama/äventyr/familj','',''),('Viasat_genre','drama/äventyr/kärlek','',''),('Viasat_genre','drama/äventyr/western','',''),('Viasat_genre','erotik','Adult',''),('Viasat_genre','erotik (klippt version)','Adult',''),('Viasat_genre','familj','',''),('Viasat_genre','familj/barn','Kids',''),('Viasat_genre','familj/fantasy','',''),('Viasat_genre','familj/musikal','Musical',''),('Viasat_genre','familj/reality/underhållning','',''),('Viasat_genre','familj/science-fiction','SciFi',''),('Viasat_genre','gameshow','Game',''),('Viasat_genre','komedi','Comedy',''),('Viasat_genre','komedi/deckare','Comedy',''),('Viasat_genre','komedi/deckare/kärlek','',''),('Viasat_genre','komedi/deckare/musikal','Comedy',''),('Viasat_genre','komedi/familj','Comedy',''),('Viasat_genre','komedi/familj/fantasy','',''),('Viasat_genre','komedi/familj/kärlek','',''),('Viasat_genre','komedi/familj/musikal','Comedy',''),('Viasat_genre','komedi/familj/skräck','',''),('Viasat_genre','komedi/fantasy','',''),('Viasat_genre','komedi/fantasy/skräck','',''),('Viasat_genre','komedi/krig','',''),('Viasat_genre','komedi/kärlek','',''),('Viasat_genre','komedi/musikal','Comedy',''),('Viasat_genre','komedi/musikal/deckare','',''),('Viasat_genre','komedi/musikal/science-fiction','Comedy',''),('Viasat_genre','komedi/science-fiction','Comedy',''),('Viasat_genre','komedi/skräck','',''),('Viasat_genre','komedi/talkshow/underhållning','',''),('Viasat_genre','komedi/underhållning','',''),('Viasat_genre','komedi/western','',''),('Viasat_genre','musikal','Musical',''),('Viasat_genre','reality','Reality',''),('Viasat_genre','reality/gameshow','',''),('Viasat_genre','reality/underhållning','',''),('Viasat_genre','science-fiction','',''),('Viasat_genre','skräck','',''),('Viasat_genre','skräck/science-fiction','',''),('Viasat_genre','specialmagasin','',''),('Viasat_genre','talkshow','Talk',''),('Viasat_genre','talkshow/underhållning','',''),('Viasat_genre','tecknat','',''),('Viasat_genre','tecknat/barn','Children\'s',''),('Viasat_genre','tecknat/familj','',''),('Viasat_genre','tecknat/familj/barn','',''),('Viasat_genre','tecknat/komedi','',''),('Viasat_genre','tecknat/komedi/familj','',''),('Viasat_genre','tecknat/komedi/musikal','',''),('Viasat_genre','tecknat/musikal/science-fiction','',''),('Viasat_genre','thriller','Mystery',''),('Viasat_genre','thriller/deckare','Mystery',''),('Viasat_genre','thriller/fantasy','',''),('Viasat_genre','thriller/film noir','',''),('Viasat_genre','thriller/film noir/deckare','',''),('Viasat_genre','thriller/film noir/kärlek','',''),('Viasat_genre','thriller/komedi','Comedy',''),('Viasat_genre','thriller/komedi/deckare','',''),('Viasat_genre','thriller/komedi/skräck','',''),('Viasat_genre','thriller/krig','',''),('Viasat_genre','thriller/kärlek','',''),('Viasat_genre','thriller/science-fiction','SciFi',''),('Viasat_genre','thriller/skräck','',''),('Viasat_genre','thriller/skräck/science-fiction','',''),('Viasat_genre','thriller/thriller','',''),('Viasat_genre','thriller/äventyr/fantasy','',''),('Viasat_genre','underhållning','',''),('Viasat_genre','western','',''),('Viasat_genre','western/western','',''),('Viasat_genre','äventyr','',''),('Viasat_genre','äventyr/dokumentär','',''),('Viasat_genre','äventyr/familj','',''),('Viasat_genre','äventyr/familj/deckare','',''),('Viasat_genre','äventyr/familj/fantasy','',''),('Viasat_genre','äventyr/fantasy','',''),('Viasat_genre','äventyr/komedi','',''),('Viasat_genre','äventyr/komedi/familj','',''),('Viasat_genre','äventyr/komedi/musikal','',''),('Viasat_genre','äventyr/krig','',''),('Viasat_genre','äventyr/kärlek','',''),('Viasat_genre','äventyr/reality/underhållning','',''),('Viasat_genre','äventyr/science-fiction','',''),('Viasat_genre','äventyr/tecknat','',''),('Viasat_genre','äventyr/tecknat/familj','',''),('Viasat_genre','äventyr/tecknat/science-fiction','',''),('Viasat_genre','äventyr/western','','');
UNLOCK TABLES;
/*!40000 ALTER TABLE `trans_cat` ENABLE KEYS */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

