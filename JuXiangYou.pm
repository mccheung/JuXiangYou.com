package JuXiangYou;

use strict;
use warnings;

use LWP::UserAgent;
use JSON;
use Data::Dumper;
use HTML::TreeBuilder;
use URI;
use URI::QueryParam;

use Encode;
use YAML::Syck qw/LoadFile/;
use FindBin qw/$Bin/;

our $DEBUG = 0;

sub new {
    my ( $class, $user, $pass ) = @_;

    my $self = {};
    $self->{ user } = $user;
    $self->{ pass } = $pass;
    $self->{ ua } = LWP::UserAgent->new(
        agent => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.9; rv:33.0) Gecko/20100101 Firefox/33.0',
        cookie_jar => {},
    );

    $self->{ url_base } = 'http://www.juxiangyou.com';


    # INIT for PC28 游戏
    $self->{ pc_28 }->{ double } = 1; # 游戏倍数
    $self->{ pc_28 }->{ last_bid_id } = undef;  #最后一次竞猜 ID
    $self->{ pc_28 }->{ last_bid_result } = undef; # 最后一次竞猜结果

    $self->{ pc_28 }->{ config } = LoadFile( "$Bin/config/pc_28.yml" );

    return bless $self, $class;
}

# 登陆模块
sub do_login {
    my $self = shift;

    return unless $self->{ user } && $self->{ pass };

    my $url = 'http://www.juxiangyou.com/login.php?act=loginDo';
    my $referer = 'http://www.juxiangyou.com/';

    $self->{ ua }->default_header( referer => $referer );

    my $post = {
        tbUserAccount => $self->{ user },
        tbUserPwd => $self->{ pass },
        isChkCode => 0,
    };

    my $res = $self->{ ua }->post( $url, $post );
    return unless $res->is_success;

    my $json = eval { from_json( $res->content ); };
    if ( $@ ) {
        print "$@\n";
        return;
    }

    return 1 if $json && $json->{ result } == 200;
    return 0;
}

# 签到功能
sub qian_dao {
    my $self = shift;

    my $url = 'http://www.juxiangyou.com/checkin.php?act=checkin&tcode=jxy&t=1';

    $self->{ ua }->default_header( 'X-Requested-With' => 'XMLHttpRequest' );
    $self->{ ua }->default_header( 'referer' => 'http://www.juxiangyou.com/checkin.php' );

    # fixme later
    my $post = {
        postkey => 1,
        _fk => '8bfd4c1790de948beb'
    };

    return 1;
}

# Check PC28 result
sub check_pc_28_result {
    my $self = shift;

    my $url = 'http://game.juxiangyou.com/luck28/index.php';
    my $res = $self->{ ua }->get( $url );
    die unless $res->is_success;

    my $t = HTML::TreeBuilder->new_from_content( $res->content );

    my $result = {};
    my @rows = $t->look_down( _tag => 'tr' );
    foreach my $row ( @rows ) {
        my $last_bid_id = $row->look_down( _tag => 'td', class => 'a1' );
        $last_bid_id = $last_bid_id->as_trimmed_text if $last_bid_id;

        my $opened = $row->look_down( _tag => 'td', class => 'a7' );
        $opened = encode( 'utf8', decode( 'gbk', $opened->as_trimmed_text ) ) if $opened;

        next unless $last_bid_id && $opened;

        my $win = $row->look_down( _tag => 'td', class => 'a6' );
        $win = $win->look_down( _tag => 'span', class => 're1' ) if $win;
        $win = $win->as_trimmed_text if $win;
        $win =~ s/,//g if $win;
        ( $win ) = $win =~ /(\d+)/ if $win;

        $result->{ $last_bid_id } = { opened => $opened, win => $win };
    }

    return $result;
}

# PC28
sub pc_28_bid {
    my $self = shift;

    my $url = 'http://game.juxiangyou.com/luck28/index.php';
    $self->{ ua }->default_header( referer => 'http://www.juxiangyou.com/' );

    my $res = $self->{ ua }->get( $url );
    return unless $res->is_success;

    my $t = HTML::TreeBuilder->new_from_content( $res->content );
    my @table28s = $t->look_down( _tag => 'a', class => 'jcbtn' );
    @table28s = map { $_->attr( 'href' ) } @table28s;

    # 得竟猜的表单
    # http://game.juxiangyou.com/luck28/betting.php?a=667208
    $table28s[-1] = 'http://game.juxiangyou.com' . $table28s[-1] unless $table28s[-1] =~ /^http/;
    $res = $self->{ ua }->get( $table28s[ -1 ] );

    my $double = $self->{ pc_28 }->{ double };
    print "当前: $double 倍\n";
    require HTTP::Request;
    my $req = HTTP::Request->new('POST' => $table28s[ -1 ] );
    $req->content_type('application/x-www-form-urlencoded');
    $req->content( $self->{ pc_28 }->{ config }->{ dan }->{ $double } );

    $res = $self->{ ua }->request( $req );
    return unless $res->is_success;

    my $html = encode( 'utf8', decode( 'gbk', $res->content ) );
    print $html if $DEBUG;

    my ( $tmp ) = $html =~ /alert\('([^']*?)'\)/;
    print "$tmp\n";
    return if $html =~ /正在开奖/;


    #落单后, 倍数+1
    if ( $html =~ /投注成功/ ) {
        my $uri = URI->new( $table28s[ -1 ] );
        #$self->{ pc_28 }->{ double }++;
        $self->{ pc_28 }->{ last_bid_id } = $uri->query_param( 'a' );
        return 1;
    }
    return ;
}

# 领取救济豆
sub get_jiuji {
    my $self = shift;

    my $url = 'http://game.juxiangyou.com/ajaxDo.php';
    $self->{ ua }->default_header( referer => 'http://game.juxiangyou.com/luck28/index.php' );
    $self->{ ua }->default_header( 'X-Requested-With' => 'XMLHttpRequest' );

    my $res = $self->{ ua }->post( $url, { act => 'relief' } );
    return unless $res->is_success;

    my $json = __decode_json( $res );

    #{"result":10000,"msg":"\u9886\u53d6\u6551\u6d4e\u8c46\u6210\u529f\uff01","reliefDou":10000,"uDou":10000}
    print $json->{ msg }, "\n" if $DEBUG;
    print $json->{ result }, "\n" if $DEBUG;

    return $json->{ result };
}

sub __decode_json {
    my $res = shift;

    my $json = eval { $res->content };
    print "$@\n" if $@ && $DEBUG;
    return if $@;

    return $json;
}

1;
