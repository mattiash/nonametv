-- MySQL dump 10.9
--
-- Host: localhost    Database: listings
-- ------------------------------------------------------
-- Server version	4.1.11-Debian_4sarge7

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `channels`
--

DROP TABLE IF EXISTS `channels`;
CREATE TABLE `channels` (
  `id` int(11) NOT NULL auto_increment,
  `display_name` varchar(100) NOT NULL default '',
  `xmltvid` varchar(100) NOT NULL default '',
  `chgroup` varchar(100) NOT NULL default '',
  `grabber` varchar(20) NOT NULL default '',
  `export` tinyint(1) NOT NULL default '0',
  `grabber_info` varchar(100) NOT NULL default '',
  `logo` tinyint(4) NOT NULL default '0',
  `def_pty` varchar(20) default '',
  `def_cat` varchar(20) default '',
  `sched_lang` varchar(4) NOT NULL default '',
  `empty_ok` tinyint(1) NOT NULL default '0',
  `url` varchar(100) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `files`
--

DROP TABLE IF EXISTS `files`;
CREATE TABLE `files` (
  `id` int(11) NOT NULL auto_increment,
  `channelid` int(11) NOT NULL default '0',
  `filename` varchar(80) NOT NULL default '',
  `successful` tinyint(1) default NULL,
  `message` text NOT NULL,
  `earliestdate` datetime default NULL,
  `latestdate` datetime default NULL,
  `md5sum` varchar(33) NOT NULL default '',
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

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
  `writers` text NOT NULL,
  `adapters` text NOT NULL,
  `producers` text NOT NULL,
  `presenters` text NOT NULL,
  `commentators` text NOT NULL,
  `guests` text NOT NULL,
  `url` varchar(100) default NULL,
  PRIMARY KEY  (`channel_id`,`start_time`),
  KEY `channel_id` (`channel_id`,`start_time`),
  KEY `batch` (`batch_id`,`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `state`
--

DROP TABLE IF EXISTS `state`;
CREATE TABLE `state` (
  `name` varchar(60) NOT NULL default '',
  `value` text,
  PRIMARY KEY  (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

--
-- Table structure for table `languagestrings`
--

DROP TABLE IF EXISTS `languagestrings`;
CREATE TABLE `languagestrings` (
  `module` varchar(32) NOT NULL default '',
  `strname` varchar(32) NOT NULL default '',
  `strvalue` text NOT NULL,
  `language` varchar(4) NOT NULL default ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

