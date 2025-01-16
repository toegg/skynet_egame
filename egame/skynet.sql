SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for id_create
-- ----------------------------
DROP TABLE IF EXISTS `id_create`;
CREATE TABLE `id_create`  (
  `type` int(11) NOT NULL,
  `count` int(11) NULL DEFAULT NULL,
  PRIMARY KEY (`type`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = latin1 COLLATE = latin1_swedish_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Records of id_create
-- ----------------------------
INSERT INTO `id_create` VALUES (1, 0);

-- ----------------------------
-- Table structure for player
-- ----------------------------
DROP TABLE IF EXISTS `player`;
CREATE TABLE `player`  (
  `role_id` bigint(20) NOT NULL COMMENT '玩家id',
  `name` varchar(255) CHARACTER SET latin1 COLLATE latin1_swedish_ci NOT NULL DEFAULT '' COMMENT '玩家名字',
  PRIMARY KEY (`role_id`) USING BTREE
) ENGINE = InnoDB CHARACTER SET = latin1 COLLATE = latin1_swedish_ci ROW_FORMAT = Dynamic;

-- ----------------------------
-- Records of player
-- ----------------------------

-- ----------------------------
-- Procedure structure for get_test
-- ----------------------------
DROP PROCEDURE IF EXISTS `get_test`;
delimiter ;;
CREATE PROCEDURE `get_test`(IN p_id int)
BEGIN
			select * from test where id=p_id;
		END
;;
delimiter ;

SET FOREIGN_KEY_CHECKS = 1;
