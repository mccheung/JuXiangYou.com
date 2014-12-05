#!/usr/bin/env perl
#
use strict;
use warnings;

use JuXiangYou;
use Data::Dumper;


my $user = 'user_name';
my $pass = 'password';
my $sleep = 30;

my $jxy = JuXiangYou->new( $user, $pass );

my $login = $jxy->do_login( );
print "已经登陆\n" if $login;


while ( 1 ) {
    # 如果没有竞猜, 则猜一次 单,  落 500 豆
    unless ( $jxy->{ pc_28 }->{ last_bid_id } ) {
        my $status = $jxy->pc_28_bid();
    }


    my $result = $jxy->check_pc_28_result(  );

    my $last_bid_id = $jxy->{ pc_28 }->{ last_bid_id };
    if ( $result && $last_bid_id && $result->{ $last_bid_id } ) {
        # 判断是否猜中
        my $res = $result->{ $last_bid_id };

        if ( $res->{ opened } eq '已开奖' ) {
            my $win = $res->{ win } || 0;
            print "已开奖, 结果赢: " . $win . "\n";
            if ( $win > 0 ) {
                # 如果中了,  则倍数归 1,  还要把 last_bid_id 清零
                $jxy->{ pc_28 }->{ double } = 1;
                $jxy->{ pc_28 }->{ last_bid_id } = undef;
            } else {
                # 如果不中,  则倍数增加
                $jxy->{ pc_28 }->{ double }++;
                $jxy->{ pc_28 }->{ last_bid_id } = undef;

                if ( $jxy->{ pc_28 }->{ double } > 3  ) {
                    $jxy->{ pc_28 }->{ double } = 1;
                }
            }
        }
    };

    print "等待休息 $sleep 秒钟\n";
    sleep ( $sleep );
}
