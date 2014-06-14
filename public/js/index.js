$(function(){
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
