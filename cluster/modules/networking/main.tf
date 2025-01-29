resource "aws_vpc" "this" {
  for_each             = var.vpc_parameters
  cidr_block           = each.value.cidr_block
  enable_dns_support   = each.value.enable_dns_support
  enable_dns_hostnames = each.value.enable_dns_hostnames
  tags = merge(each.value.tags, {
    Name : each.key
  })
}

resource "aws_subnet" "this" {
  for_each                = var.subnet_parameters
  vpc_id                  = aws_vpc.this[each.value.vpc_name].id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.map_public_ip_on_launch
  tags = merge(each.value.tags, {
    vpc-id : aws_vpc.this[each.value.vpc_name].id
    Name : each.key
  })
}

resource "aws_internet_gateway" "this" {
  for_each = var.igw_parameters
  vpc_id   = aws_vpc.this[each.value.vpc_name].id
  tags = merge(each.value.tags, {
    vpc-id : aws_vpc.this[each.value.vpc_name].id
    Name : each.key
  })
}

resource "aws_route_table" "this" {
  for_each = var.rt_parameters
  vpc_id   = aws_vpc.this[each.value.vpc_name].id
  tags = merge(each.value.tags, {
    vpc-id : aws_vpc.this[each.value.vpc_name].id
    Name : each.key
  })

  dynamic "route" {
    for_each = each.value.routes
    content {
      cidr_block     = route.value.cidr_block
      gateway_id     = route.value.use_igw ? aws_internet_gateway.this[route.value.gateway_id].id : null
      nat_gateway_id = route.value.use_ngw ? aws_nat_gateway.this[route.value.gateway_id].id : null
    }
  }
}

resource "aws_route_table_association" "this" {
  for_each       = var.rt_association_parameters
  subnet_id      = aws_subnet.this[each.value.subnet_name].id
  route_table_id = aws_route_table.this[each.value.rt_name].id
}

resource "aws_eip" "this" {
  for_each = var.ngw_parameters
  domain   = "vpc"
  tags = merge(each.value.tags, {
    Name : each.value.eip_name
  })
}

resource "aws_nat_gateway" "this" {
  for_each      = var.ngw_parameters
  allocation_id = aws_eip.this[each.key].id
  subnet_id     = aws_subnet.this[each.value.subnet_name].id
  tags = merge(each.value.tags, {
    Name : each.key
  })
}
