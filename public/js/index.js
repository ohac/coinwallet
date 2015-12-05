$(function(){
  var hash = location.hash;
  if (hash.length > 0) {
    var coinid = hash.split('/')[1];
    $('.coininfo').hide();
    $('#' + coinid + '-c').show();
  }
  else {
    $('#warn').show();
  }
  $('.selectcoin').click(function(){
    var menu = $(this);
    var coinid = menu.attr('id');
    $('.coininfo').hide();
    $('#' + coinid + '-c').show();
    $('#warn').hide();
  });
  $('span.balance').each(function(){
    var id = $(this).attr('id');
    var coinid = id.split('_')[1];
    $.ajax({
      url: '/api/v1/' + coinid + '/balance',
      cache: false,
      dataType: 'json',
      success: function(json){
        var balance = json['balance'];
        var balance0 = json['balance0'] - balance;
        var str = balance > 0.00005 ? (balance - 0.00005).toFixed(4) : '0.0000';
        $('#' + id).text(str);
        if (balance0 > 0.00005) {
          str = (balance0 - 0.00005).toFixed(4);
          $('#' + id + '_incoming').text('(' + str + ')');
        }
      }
    });
  });
});
