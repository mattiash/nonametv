-- MySQL dump 10.10
--
-- Host: localhost    Database: listings
-- ------------------------------------------------------
-- Server version	5.0.18-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `lang_se`
--

DROP TABLE IF EXISTS `lang_se`;
CREATE TABLE `lang_se` (
  `module` varchar(32) NOT NULL,
  `strname` varchar(32) NOT NULL,
  `strvalue` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Dumping data for table `lang_se`
--


/*!40000 ALTER TABLE `lang_se` DISABLE KEYS */;
LOCK TABLES `lang_se` WRITE;
INSERT INTO `lang_se` (`module`, `strname`, `strvalue`) VALUES ('exporter-xmltv','episode_part','Part'),('exporter-xmltv','episode_number','Del'),('exporter-xmltv','episode_season','säsong'),('exporter-xmltv','of','av'),('listchannels','title','This is the title of your channel listing page.'),('listchannels','headertext','Put whatever you want here. It will be displayed on the top of the channel list.'),('listchannels','channel','Channel'),('listchannels','xmltvid','XMLTV ID'),('listchannels','datasource','Source'),('listchannels','footertext','Put whatever you want here. It will be displayed on the bottom of the channel list.');
UNLOCK TABLES;
/*!40000 ALTER TABLE `lang_se` ENABLE KEYS */;

--
-- Table structure for table `lang_hr`
--

DROP TABLE IF EXISTS `lang_hr`;
CREATE TABLE `lang_hr` (
  `module` varchar(32) NOT NULL,
  `strname` varchar(32) NOT NULL,
  `strvalue` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Dumping data for table `lang_hr`
--


/*!40000 ALTER TABLE `lang_hr` DISABLE KEYS */;
LOCK TABLES `lang_hr` WRITE;
INSERT INTO `lang_hr` (`module`, `strname`, `strvalue`) VALUES ('exporter-xmltv','episode_part','dio'),('exporter-xmltv','episode_number','epizoda'),('exporter-xmltv','episode_season','sezona'),('exporter-xmltv','of','od'),('listchannels','title','Kanali za koje goNIX ima raspored emitiranja'),('listchannels','headertext','Rasporedi programa svih navedenih kanala nalaze se u <a href=\"/xmltv/\">XMLTV</a> direktoriju. Za svaki dan i svaki kanal kreira se po jedan file.'),('listchannels','channel','Kanal'),('listchannels','xmltvid','XMLTV ID'),('listchannels','datasource','Izvor'),('listchannels','footertext','');
UNLOCK TABLES;
/*!40000 ALTER TABLE `lang_hr` ENABLE KEYS */;

--
-- Table structure for table `lang_en`
--

DROP TABLE IF EXISTS `lang_en`;
CREATE TABLE `lang_en` (
  `module` varchar(32) NOT NULL,
  `strname` varchar(32) NOT NULL,
  `strvalue` text NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Dumping data for table `lang_en`
--


/*!40000 ALTER TABLE `lang_en` DISABLE KEYS */;
LOCK TABLES `lang_en` WRITE;
INSERT INTO `lang_en` (`module`, `strname`, `strvalue`) VALUES ('exporter-xmltv','episode_part','part'),('exporter-xmltv','episode_number','episode'),('exporter-xmltv','episode_season','season'),('exporter-xmltv','of','of'),('listchannels','title','This is the title of your channel listing page.'),('listchannels','headertext','Put whatever you want here. It will be displayed on the top of the channel list.'),('listchannels','channel','Channel'),('listchannels','xmltvid','XMLTV ID'),('listchannels','datasource','Source'),('listchannels','footertext','Put whatever you want here. It will be displayed on the bottom of the channel list.');
UNLOCK TABLES;
/*!40000 ALTER TABLE `lang_en` ENABLE KEYS */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

